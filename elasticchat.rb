#!/usr/bin/env ruby

# gem install sinatra sinatra-contrib thin bson_ext mongodb

require 'sinatra'
require 'sinatra/streaming'
require 'sinatra/cookies'
require 'mongo'
require 'json'
require 'digest/sha2'
require 'ap'
require './spine'
require './tokens'
require 'sinatra/reloader'
include Mongo # Import mongo symbols for convenience

configure do
  set :server, :thin
end

iv =  Digest::SHA2.new(256).digest("FBDfsdfrvyh8i67qc34x123e1w4rcq$Wtaw4twyj")
key = Digest::SHA2.new(256).digest("asasjhsdfFERt45y4hg3$&kjgfgf$Wsdcvl8*r6t")

db = MongoClient.new("localhost", 27017).db("elasticchat")

topics = Hash.new
topics["test"] = MongoChat.new("test",db,key,iv) # Make sure we always have our base channel
  
get '/' do
  "<center>I feel sorry for people who don't drink.<br> 
  When they wake up in the morning,<br> 
  that's as good as they're going to feel all day.<br>
  <br>
  -- Frank Sinatra<br></center>"
end

get '/subscribe/:topic/:epoch_stamp', :provides => 'text/html' do |topic,epoch|
  topics[topic] = MongoChat.new(topic,db,key,iv) unless topics.has_key?(topic)
   
  stream :keep_open do |out|
    # Dump all of the historical
    topics[topic].read({ :filter => "since:#{epoch}", :raw => true }).each do |message|
      out << topics[topic].format_message(message) if topics[topic].to_me?(message,out)
    end 
    
    # Carry on
    EventMachine::PeriodicTimer.new(20) { out << topics[topic].HEARTBEAT }
    topics[topic].connections << out
    out.callback { topics[topic].connections.delete(out) }
  end

end

get '/subscribe/:topic', :provides => 'text/html' do |topic|
  topics[topic] = MongoChat.new(topic,db,key,iv) unless topics.has_key?(topic)
  token = SecureToken.new(key,iv)
  token.payload = "A USER NAME"
  cookies[:session] = token.to_e(true)
    
  stream :keep_open do |out|
    EventMachine::PeriodicTimer.new(20) { out << topics[topic].HEARTBEAT }
    topics[topic].connections << out
    out.callback { topics[topic].connections.delete(out) }
  end

end

post '/publish/:topic/:message' do
#get '/publish/:topic/:message/:style/:touser' do |t,m,s,u|
  # TODO: Hook in authentication requirement here
  
  topic = Sanitize.clean(params[:topic], Sanitize::Config::RESTRICTED)
  message = Sanitize.clean(params[:message], Sanitize::Config::RELAXED)
  style = Sanitize.clean(params[:style], Sanitize::Config::RESTRICTED)
  toUser = Sanitize.clean(params[:to], Sanitize::Config::RESTRICTED)
  toUser = nil if toUser == 'all'
  #topic = t
  #message = m
  #style = s
  #toUser = u
  #toUser = nil if toUser == 'all' 
  
   
  # Instantiate the room in this instance if needed
  topics[topic]  = MongoChat.new(topic,db,key,iv) unless topics.has_key?(topic)

  stream do |out|
    fromUser = topics[topic].user_from_connection(out)
    topics[topic].add({:message => message, :from => fromUser, :style => style, :user => toUser }, {:raw => true})
    out << "Sent"
  end
  
end

get '/whois/:topic', :provides => 'text/plain' do |topic|
  topics[topic]  = MongoChat.new(topic,db,key,iv) unless topics.has_key?(topic)
  
  topics[topic].connected
end

get '/topics', :provides => 'text/plain' do
  
  topics["test"].topics.join(', ')
 
end

get '/debug', :provides => 'text/plain' do
  stream do |out|
    out.puts topics["test"].user_from_connection(topics["test"].connections[0])
  end
end
  
