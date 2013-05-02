# source map support for coffee-script ~1.6.1
require('source-map-support').install()

require('should')
expect = require('expect.js')
request = require('request')

port = process.env.PORT || 2345
baseUrl = "http://localhost#{if port then ':'+port else ''}/"
displayServerRequest = false


namespace = "/db/"
baseHref = baseUrl+"db/"

#### TESTAPPLICATION

express = require("express")
http = require("http")
path = require("path")

mongoose = require("mongoose")
mongoose.connect("mongodb://localhost/mongraphrestful_example")

neo4j = require("neo4j")
graphdb = new neo4j.GraphDatabase("http://localhost:7474")

mongraphRESTful = require("../src/mongraphrestful")
mongraphRESTful.init { mongoose: mongoose, neo4j: graphdb, namespace: namespace }

Person = mongoose.model("Person", name: String)

app = express()

app.set "port", port
app.set "views", __dirname + "/../views"
app.set "view engine", "jade"
app.use express.favicon()
app.use express.logger("dev") if displayServerRequest
app.use express.bodyParser()
app.use express.methodOverride()
#### apply -->
mongraphRESTful.applyRoutes(app)
#### <-- apply
app.use app.router
app.use express.static(path.join(__dirname, "/../public"))

# development only
app.use express.errorHandler()  if "development" is app.get("env")
app.get "/", (req, res) -> res.render 'index', { title: 'Express' }

fullUrlFor = (url, doLog = false) ->
  url = baseHref+url.replace(/^\/+/, '')
  console.log('--> '+url) if doLog
  url

describe 'mongraph restful', ->

  alice = bob = foo = bar = null;

  before (done) ->
    # START SERVER
    http.createServer(app).listen app.get("port"), ->
      console.log "Express server listening on port " + app.get("port")
      request.del url: fullUrlFor('/people'), (err, res) ->
        # 204 or 404
        expect(res.statusCode).to.be.above 203
        expect(res.statusCode).to.be.below 405
        done()

  beforeEach (done) ->
    # create example record
    a = { person: { name: 'Alice' } }
    b = { person: { name: 'Bob' } }
    request.post { url: fullUrlFor('/people'), body: JSON.stringify(a), headers: { 'Content-Type': 'application/json' } }, (err, res1) ->
      request.post { url: fullUrlFor('/people'), body: JSON.stringify(b), headers: { 'Content-Type': 'application/json' } }, (err, res2) ->
        # on the first run we can't make a request, so we catch the parsing error and don't set alice
        try
          alice = JSON.parse(res1.body)?.person
          bob   = JSON.parse(res2.body)?.person
        catch error
          alice = null
          bob   = null
        expect(alice._id).not.to.be null
        expect(bob._id).not.to.be null
        done()

  describe 'utils', ->

    describe '#optimizeValuesOnObject()', ->

      it 'expect to cast values correctly', ->
        data = { test: key: '/^[a-z]+$/' }
        mongraphRESTful.utils.optimizeValuesOnObject(data)
        expect(data.test.key).to.be.an RegExp
        expect(data.test.key.test('test')).to.be true
  
  describe 'routes', ->
 
    it 'expect to reach server on '+baseUrl, (done) ->
      request.get baseUrl, (err, res) ->
        expect(res.statusCode).to.be 200
        done()

    it 'expect to get all collections with schema listed', (done) ->
      request.get fullUrlFor('/collections'), (err, res) ->
        body = JSON.parse(res.body)
        expect(err).to.be.null
        expect(body.people.schema.name.instance).to.be 'String'
        done()

    it 'expect to get all documents of a collection', (done) ->
      request.get fullUrlFor('/people'), (err, res) ->
        expect(res.statusCode).to.be 200
        data = JSON.parse(res.body)
        expect(data.people.length).to.be.above 0
        done()

    it 'expect to get one document of a collection', (done) ->
      request.get fullUrlFor('/people/one'), (err, res) ->
        expect(res.statusCode).to.be 200
        body = JSON.parse(res.body)
        expect(body.person._id).to.be.a 'string'
        done() 

    it 'expect to remove all documents of a collection', (done) ->
      request.del fullUrlFor('/people'), (err, res) ->
        expect(res.statusCode).to.be.above 203 # 204 or 404
        expect(res.statusCode).to.be.below 405
        done()

    it 'expect to query documents', (done) ->
      data = person: name: 'New Name'
      request.post
        url: fullUrlFor('/people')
        body: JSON.stringify(data)
        headers: 'Content-Type': 'application/json'
        , ->
          where =
            name: '/^New/'
          request.get
            url: fullUrlFor('/people')
            headers:
              where_document: JSON.stringify(where)
          , (err, res) ->
            body = JSON.parse(res.body)
            expect(body.people[0].name).be.equal 'New Name'
            done()

    it 'expect to update a document', (done) ->
      data = person: name: 'Alice Springs'
      url  = fullUrlFor('/people/'+alice._id)
      request.put {
        url: url,
        body: JSON.stringify(data)
        headers: 'Content-Type': 'application/json'
      }, (err, res) ->
        expect(err).to.be null
        body = JSON.parse(res.body)
        expect(body.person.name).to.be.equal = 'Alice Springs'
        done()

    it 'expect to get a document by id', (done) ->
      request.get fullUrlFor('/people/'+alice._id), (err, res) ->
        expect(err).to.be null
        body = JSON.parse(res.body)
        expect(body.person._id).to.be.equal alice._id
        done()

    it 'expect to create different kind of relationships and directions of a document', (done) ->
      request.post
        url: fullUrlFor('/people/'+alice._id+'/relationship/to/people/'+bob._id+'/knows')
        body: JSON.stringify({ since: 'now' })
        headers: 'Content-Type': 'application/json'
        , (err, res, options) ->
          data = JSON.parse(res.body).relationship
          expect(data.id).be.above 0
          expect(data.from.name).to.be 'Alice'
          expect(data.to.name).to.be 'Bob'
          expect(data.data.since).to.be 'now'
          done()

    it 'expect to get different kind of relationships of a document', (done) ->
      request.post
        url: fullUrlFor('/people/'+alice._id+'/relationship/between/people/'+bob._id+'/knows')
        body: JSON.stringify({ since: 'now' })
        headers: 'Content-Type': 'application/json'
        , (err, res) ->
          expect(err).to.be null
          request.get fullUrlFor('/people/'+alice._id+'/relationships/outgoing/knows'), (err, res) ->
            data = JSON.parse(res.body).relationships
            expect(data).to.have.length 1
            expect(data[0].type).to.be 'knows'
            done()

    it 'expect to delete different kind of relationships', (done) ->
      request.post
        url: fullUrlFor('/people/'+alice._id+'/relationship/between/people/'+bob._id+'/knows')
        body: JSON.stringify({ since: 'now' })
        headers: 'Content-Type': 'application/json'
        , (err, res) ->
          expect(err).to.be null
          request.get fullUrlFor('/people/'+alice._id+'/relationships/all/knows'), (err, res) ->
            data = JSON.parse(res.body).relationships
            expect(data).to.have.length 2
            request.del fullUrlFor('/people/'+alice._id+'/relationships/outgoing/knows'), (err, res) ->
              expect(err).to.be.null
              expect(res.statusCode).to.be 204
              request.get fullUrlFor('/people/'+alice._id+'/relationships/all/knows'), (err, res) ->
                data = JSON.parse(res.body).relationships
                expect(data).to.have.length 1
                request.del fullUrlFor('/people/'+alice._id+'/relationships/incoming/knows'), (err, res) ->
                  expect(err).to.be null
                  request.get fullUrlFor('/people/'+alice._id+'/relationships/all/knows'), (err, res) ->
                    data = JSON.parse(res.body).relationships
                    expect(data).to.be null
                    done()

    it 'expect to get, update and delete a relationship by id', (done) ->
      request.post
        url: fullUrlFor('/people/'+alice._id+'/relationship/to/people/'+bob._id+'/knows')
        body: JSON.stringify({ since: 'now' })
        headers: 'Content-Type': 'application/json'
        , (err, res) ->
          expect(err).to.be.null
          request.get fullUrlFor('/people/'+alice._id+'/relationships/all/knows'), (err, res) ->
            data = JSON.parse(res.body)
            expect(data.relationships).to.have.length 1
            id = data.relationships[0].id
            expect(id).to.be.above 0
            request.get fullUrlFor('/relationship/'+id), (err, res) ->
              expect(err).to.be null
              data = JSON.parse(res.body)
              relationship = data.relationship
              expect(relationship).to.be.an 'object'
              expect(relationship.data.since).to.be.equal 'now'
              expect(relationship.id).to.be.equal id
              data = relationship: since: 'years', _created_at: null
              request.put {
                url: fullUrlFor('/relationship/'+id),
                body: JSON.stringify(data)
                headers: 'Content-Type': 'application/json'
              }, (err, res) ->
                expect(err).to.be null
                data = JSON.parse(res.body)
                expect(data.relationship.data.since).to.be.equal 'years'
                expect(data.relationship.id).to.be.equal id
                request.del fullUrlFor('/relationship/'+id), (err, res) ->
                  expect(err).to.be.null
                  expect(res.statusCode).to.be 204
                  request.get fullUrlFor('/relationship/'+id), (err, res) ->
                    expect(err).to.be.null
                    expect(res.statusCode).to.be 404
                    done()

