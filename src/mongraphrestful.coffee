_    = require 'underscore'
Join = require 'join'

mongraph = require 'mongraph'

_dbhandler = {} # will be set in ini

class MongraphUtil

  removeFilteredAttributes: (o, filter = /^_/) ->
    # TODO: recursive
    for attr of o
      delete o[attr] if filter.test(attr)
    o

  removeNullAttributes: (o) ->
    if typeof o is 'object' and Object.keys(o).length > 0
      for attr of o
        MongraphUtil::removeNullAttributes(o[attr]) if o[attr]
        delete o[attr] if o[attr] is null
    o

  optimizeValuesOnObject: (o) ->
    # find and replace regexpression-string with regex objects, recursive
    if typeof o is 'object' and Object.keys(o).length > 0
      for attr of o
        value = o[attr]
        if value
          MongraphUtil::optimizeValuesOnObject(o[attr])
          o[attr] = new RegExp(o[attr].replace(/^\/(.+)\/$/, '$1')) if typeof value is 'string' and value.match(/^\/.+/)


class MongraphDocuments

  documentToObjectOptions: ->
    { getters: true, virtuals: false }

  documentToObject: (doc) ->
    # TODO: type check
    # mongoose document
    doc = doc.toObject()#document.documentToObjectOptions()
    # delete doc._relationships ?= null
    delete doc.__v
    doc

  documentToJson: (document, cb) ->
    
    self = @

    constructorName = mongraph.processtools.constructorNameOf(document)

    if constructorName is 'model'
      # mongraph
      unless typeof document?.applyGraphRelationships is 'function'
        cb Error('No document object given'), null
      else unless document?._node_id > 0
        cb Error('No attached noded found'), if doc?.toObject then MongraphDocuments::documentToObject(document) else null
      else
        document?.applyGraphRelationships { doPersist: false }, (err, doc) ->
          cb err, if document?.toObject then MongraphDocuments::documentToObject(document) else null
    else
      # graphdb object
      # build from scratch
      data =
        id: document.id
        type: document.type
        constructor: constructorName
      data.data = document.data if document.data
      data.from = MongraphDocuments::documentToObject(document.from) if document.from
      data.to   = MongraphDocuments::documentToObject(document.to) if document.from
      cb null, data

  documentsToJson: (documents, cb) ->
    joinWhen = false
    join = Join.create()
    if documents?.constructor is Array
      for doc in documents
        cbDoc = join.add()
        joinWhen = true
        do (doc, cbDoc) ->
          MongraphDocuments::documentToJson(doc, cbDoc)
    else if typeof documents is 'object'
      cbObj = join.add()
      joinWhen = true
      MongraphDocuments::documentToJson(documents, cbObj)

    return cb(null,null) unless joinWhen
    
    join.when ->
      docs = []
      for result in arguments
        docs.push(result[1]) if result[1]
      cb null, docs

class MongraphRoutes

  extractFromRequest: (req) ->
    limit = skip = collectionName = collectionTo = collectionFrom = collection = model = parameters = body = data = where = _id = _idFrom = _idTo = null
    body       = req?.body      
    parameters = req?.sortedParams
    if parameters
      _id     = parameters._id || parameters._id_from || null
      _idFrom = parameters._id_from || null
      _idTo   = parameters._id_to   || null
      if parameters?.collection_name or parameters?.collection_from or parameters?.collection_to
        # use collection as fallback
        collectionName  = parameters?.collection_name || parameters?.collection_from
        collection      = mongraph.processtools.getCollectionByCollectionName(collectionName) if collectionName
        model           = mongraph.processtools.getModelByCollectionName(collectionName)      if collectionName

        modelName = model?.modelName

        # do we have a from and to collection?
        collectionTo    = mongraph.processtools.getModelByCollectionName(req.sortedParams.collection_to)    if req.sortedParams?.collection_to
        collectionFrom  = mongraph.processtools.getModelByCollectionName(req.sortedParams.collection_from)  if req.sortedParams?.collection_from

        if req.body?[modelName.toLowerCase()]
          data = req.body?[modelName.toLowerCase()]
      {limit,where,skip} = req.query
      # prefer where from header form if given
      where = req.headers?.where if req.headers?.where
      # prefer *more* where query from body if given
      where = body.where if body.where
      if typeof where is 'string'
        try
          where = JSON.parse(where)
        catch e
          where = {}
        MongraphUtil::optimizeValuesOnObject(where)
      # TODO: maybe to an opt out for disabling where statements?!
    where ?= {}
    {collectionName, collectionTo, collectionFrom, collection, parameters, where, body, model, modelName, data, _idFrom, _idTo, _id}

  responseWith: (req, res, err, data, options = {}) ->
    # make to lowercase because mongoose is using CamelCase for model name
    options.context = options.context.toLowerCase() if options.context
    if err
      code = err?.code || options.statusCode || 500
      res.json { error: err?.message || err, code: code }, code
    else if typeof data isnt 'undefined' and typeof data isnt 'object'
      options.statusCode  ?= 200
      res.json { data: { value: data } }, options.statusCode
    else if data
      options.statusCode  ?= 200
      # expect to be an object
      if mongraph.processtools.constructorNameOf(data)# is 'model'
        MongraphDocuments::documentsToJson data, (err, preparedData) ->
          preparedData = preparedData[0] if options.asList isnt true
          apiData = { data: preparedData }
          if options?.context
            apiData = {}
            apiData[options.context] = preparedData
          # TODO: instead of options.context detect by first/only key?!
          # if Object.keys(data).length > 1
          #   # put all object data into an `anonymous` dataobject
          #   apiData = { data: preparedData }
          # else
          #   # else use first and only attribute as context
          #   # e.g: { realtionship: { ... } }
          #   apiData = {}
          #   apiData[data[Object.keys(data)[0]]] = preparedData
          res.json apiData, options.statusCode
      else
        # unknown object
        res.json { data: data }, options.statusCode
    else
      res.send 'not found', options?.statusCode || 404

  all_documents: (req, res, next, options = {}) ->
    {collectionName,collection,where} = MongraphRoutes::extractFromRequest(req)
    options.context ?= collectionName
    options.asList  ?= if options.oneDocument is true then false else true
    if collection
      # find or findOne ?
      findMethod = if options.oneDocument then 'findOne' else 'find'
      where ?= {}
      collection[findMethod] where, (err, docs) ->
        MongraphRoutes::responseWith req, res, err, docs, options
    else
      res.send 'collection not found', 404

  one_document: (req, res) ->
    {modelName} = MongraphRoutes::extractFromRequest(req)
    MongraphRoutes::all_documents req, res, undefined, { oneDocument: true, context: modelName }

  remove_all_documents: (req, res) ->
    {collection} = MongraphRoutes::extractFromRequest(req)
    collection.remove {}, (err, count) ->
      MongraphRoutes::responseWith req, res, null, count, { statusCode: if count > 0 then 204 else 404 }

  get_document: (req, res) ->
    {collection,parameters,modelName} = MongraphRoutes::extractFromRequest(req)
    collection.findById parameters._id, (err, found) ->
      MongraphRoutes::responseWith req, res, err, found, { asList: false, context: modelName }

  remove_document: (req, res) ->
    {collection,parameters} = MongraphRoutes::extractFromRequest(req)
    collection.remove { _id: parameters._id }, (err, count) ->
      MongraphRoutes::responseWith req, res, err, '', { statusCode: if count > 0 then 204 else 404 }

  update_document: (req, res) ->
    {collection,parameters,data,modelName} = MongraphRoutes::extractFromRequest(req)
    # remove all _underscored attributes from 1st level
    data = MongraphUtil::removeFilteredAttributes(data, /^_/)
    collection.update { _id: parameters._id }, data, (err, status) ->
      collection.findById parameters._id, (err, document) ->
        MongraphRoutes::responseWith req, res, err, document, { asList: false, context: modelName }

  create_document: (req, res) ->
    {model,parameters,data} = MongraphRoutes::extractFromRequest(req)
    document = new model(data)
    document.save (err, created) ->
      MongraphRoutes::responseWith req, res, err, document, { statusCode: 201, asList: false }#, { headers: Location: 'not implemented', asList: false }


  relationships: (req, res) ->
    model = parameters = type = direction = null
    _from_id = _id_to = collection_from = collection_to = null
    fromDocument = toDocument = null

    doCreateRelationship = req.method is 'POST'
    
    {model,parameters,collection, collectionTo, collectionFrom, _idTo, _idFrom} = MongraphRoutes::extractFromRequest(req)
    
    # additionally needed parameters for this method
    {type,direction} = req.sortedParams

    join = Join.create()

    for point in [ 'from', 'to' ]
      do (point) ->
        _id        = if point is 'to' then _idTo        else _idFrom
        collection = if point is 'to' then collectionTo else collectionFrom
        if collection and _id
          callback = join.add()
          collection.findById _id, callback

    join.when ->

      from = arguments?['0']?[1] || null
      to   = arguments?['1']?[1] || null

      endNodeId   = to._node_id if to
      processPart = 'r'
      
      renderOptions = {}
      renderOptions.asList  = true
      renderOptions.context = 'relationships'

      data = req.body || {}

      if req.method is 'POST' and from and to
        renderOptions.asList     = false
        renderOptions.context    = 'relationship'
        renderOptions.statusCode =  201
        # create relationship
        methodName = switch parameters.direction
          when 'to'      then 'createRelationshipTo'
          when 'from'    then 'createRelationshipFrom'
          when 'between' then 'createRelationshipBetween'
        return from[methodName] to, type, data, (err, relationships) ->
          MongraphRoutes::responseWith req, res, err, relationships, renderOptions
      else if req.method is 'DELETE'
        action = 'DELETE'
        renderOptions.statusCode = 204
      else if req.method is req.method is 'GET'
        action = 'RETURN'
      else
        return MongraphRoutes::responseWith req, res, Error('Could not detect a valid operation'), null

      options = {direction,endNodeId,processPart,action}

      from.queryRelationships type, options, (err, relationships, options) ->
        MongraphRoutes::responseWith req, res, err, relationships, renderOptions

  relationship: (req, res) ->
    {parameters} = MongraphRoutes::extractFromRequest(req)
    id = parameters.id
    if /^[1-9]+[0-9]*$/.test(id)
      _dbhandler.neo4j.getRelationshipById id, (err, relationship) ->
        if err and JSON.stringify(err).match(/RelationshipNotFoundException/)
          err = Error('Relationship not found')
          err.code = 404
          MongraphRoutes::responseWith(req, res, err, null)
        else
          if req.method is 'GET'
            MongraphRoutes::responseWith req, res, null, relationship, { asList: false, context: 'relationship' }
          else if req.method is 'PUT'
            data = req.body?.relationship || null
            # remove underscored values
            data = MongraphUtil::removeFilteredAttributes(data, /^_/)
            _.extend(relationship.data, data)
            relationship.data = MongraphUtil::removeNullAttributes(relationship.data)
            relationship.save (err, savedRelationship) ->
              MongraphRoutes::responseWith req, res, null, savedRelationship, { asList: false, context: 'relationship' }
          else if req.method is 'DELETE'
            relationship.delete (err, result) ->
              MongraphRoutes::responseWith req, res, err || null, null, statusCode: 204
    else
      MongraphRoutes::responseWith req, res, Error('No id given'), null


class MongraphRestful

  _options:
    dbhandler: {}
    namespace: '/'

  _routes:
    'GET:             :collection_name/*':                                                               MongraphRoutes::all_documents
    'GET:             :collection_name/one/*':                                                           MongraphRoutes::one_document
    'DELETE:          :collection_name':                                                                 MongraphRoutes::remove_all_documents
    'POST:            :collection_name':                                                                 MongraphRoutes::create_document
    'GET:             :collection_name/:_id':                                                            MongraphRoutes::get_document
    'DELETE:          :collection_name/:_id':                                                            MongraphRoutes::remove_document
    'PUT:             :collection_name/:_id':                                                            MongraphRoutes::update_document
    'GET|DELETE:      :collection_from/:_id_from/relationships/:direction/:type':                        MongraphRoutes::relationships
    'GET|DELETE:      :collection_from/:_id_from/relationships/:direction/:collection_to/:_id_to/:type': MongraphRoutes::relationships
    'POST:            :collection_from/:_id_from/relationship/:direction/:collection_to/:_id_to/:type':  MongraphRoutes::relationships
    'GET|PUT|DELETE:  relationship/:id':                                                                 MongraphRoutes::relationship

  routes: (routes) ->
    _.extend(@_routes, routes) if routes
    segment_pattern = /\:(_*[a-zA-Z\_]+)/g
    _id_pattern     = /\:_id(_[a-z]+)*/g
    for route, func of @_routes
      # TODO: do a good warning
      # throw new Error("The method for defined route '#{route}' doesn't exists") unless func
      methods = route.match(/^([A-Z|]+?)\:/)?[1]?.split('|') || 'GET|POST|DELETE|UPDATE'.split('|')    
      route   = route.replace(/^([A-Z|]+?\:)/, '').trim() if methods # strip method from route
      matches = route.match(segment_pattern)
      if matches?.length > 0
        { methods: methods, segments: matches, route: '^' + @_options.namespace + route.replace(_id_pattern, '([0-9a-f]{24,25})').replace(segment_pattern, '([a-zA-Z0-9]+)') + '$', segments: matches, action: func }
      else
        { methods: methods, segments: matches, route: '^' + @_options.namespace + route + '$', action: func }

  applyRoutes: (app) ->
    listOfRoutes = []
    for part in routes = @routes()
      route   = new RegExp(part.route.replace(/\//g,"\\/"))
      for method in part.methods
        # each action needs his own scope
        listOfRoutes.push(method.toLowerCase()+':'+route)
        do (route, method, part) ->
          app[method.toLowerCase()] route, (req,res,next) ->
            req.sortedParams ?= {}
            if req.params
              for param, i in req.params
                req.sortedParams[part.segments[i].replace(/^\:/,'')] = param
            part.action(req,res,next)
    listOfRoutes

  init: (options) ->
    _.extend(@_options, options)
    @_options.dbhandler.mongoose = options.mongoose
    @_options.dbhandler.neo4j    = options.neo4j
    _dbhandler = @_options.dbhandler
    mongraph.init { mongoose: options.mongoose, neo4j: options.neo4j }

  options: -> @_options

  utils: new MongraphUtil()

application = new MongraphRestful()

exports = module.exports = application
