elasticbus
==========

An intelligent, adaptable, distributed framework for Registration, Presence, and Communication

* Ruby
* Sinatra
* MongoDB

'elasticchat' is included as a reference implementation of the bus, to aid in debugging during development.
Just run `ruby ./elasticchat.rb myroom` and then hit point your browser at http://localhost:4567/

Protocol

* SSE over HTTP[S]


* /register/systemname
* /subscribe/topic1/systemname .. /subscribe/topicN/systemname
* /publish/topicX