# MongraphRESTful

[![Build Status](https://api.travis-ci.org/pstaender/mongraph.png)](https://travis-ci.org/pstaender/mongraph)

Provides a restful (database-like) service to manage documents with graph relationships. Powered by mongoose, neo4j and mongraph.

## Proof of concept

Should demonstrate that **mongodb** and **neo4j** can work together as one service (-> mongraph[RESTful]).

## Issues

There are no performance and benchmark tests made, yet -> so there is room for improvement ;)

Also there is **no security / acl / auth** implemented, so this api should never be for any public access. Use expressjs to secure your api (e.g. basic http auth, ssl etc).

## Usage

* create or open your existing expressjs app
* clone this repository (not in npm, yet) to your local app folder `git clone git@github.com:pstaender/mongraphrestful.git mongraphrestful`
* go to the cloned folder and install dependencies `cd mongraphrestful && npm install .` 
* and apply mongraph in your `app.js` or `app.coffee` as shown:

```coffeescript

  express = require("express")
  http = require("http")
  path = require("path")

  # Setup your mongodb + neo4j db
  mongoose = require("mongoose")
  mongoose.connect("mongodb://localhost/mongraphrestful_example")
  neo4j = require("neo4j")
  graphdb = new neo4j.GraphDatabase("http://localhost:7474")

  # load mongraphrestful, pass through the neo4j and mongoose handler
  mongraphRESTful = require("mongraphrestful")
  mongraphRESTful.init { mongoose: mongoose, neo4j: graphdb, namespace: '/api/v1/' }

  # Define your schemas as usual
  Person = mongoose.model("Person", name: String)

  # configure expressjs as usual
  app = express()

  app.set "port", port
  app.set "views", __dirname + "/../views"
  app.set "view engine", "jade"
  app.use express.favicon()
  app.use express.logger("dev")
  app.use express.bodyParser()
  app.use express.methodOverride()

  # THIS IS WHERE THE ROUTES ARE APPLIED TO YOUR EXPRESSJS APP
  # ------>
  
  mongraphRESTful.applyRoutes(app)
  
  # <------

  app.use app.router

  ...
  
```

## Available Routes

* `:collection_name` could be `people` for instance
* `:_id`, `:_id_from` and `:_id_to` ObjectID(s) of your document(s)
* `:direction` can be `incoming`, `outgoing` or `all`
* `:type` could be `knows` for instance
* `:id` is an integer number for a relationship in neo4j

```
  GET:             :collection_name
  GET:             :collection_name/one
  DELETE|POST:     :collection_name
  GET|PUT|DELETE:  :collection_name/:_id
  GET|DELETE:      :collection_from/:_id_from/relationships/:direction/:type
  GET|DELETE:      :collection_from/:_id_from/relationships/:direction/:collection_to/:_id_to/:type
  POST:            :collection_from/:_id_from/relationship/:direction/:collection_to/:_id_to/:type
  GET|PUT|DELETE:  relationship/:id
```

## Tests and examples

`npm test`

## License

Mongraphrestful is available under the GPL v3, see `LICENSE` file for further details.
