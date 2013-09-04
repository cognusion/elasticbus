#!/usr/bin/env ruby

# gem install sinatra sinatra-contrib thin bson_ext mongodb

require 'sinatra'
require 'sinatra/streaming'
require 'sinatra/cookies'
require 'mongo'
require 'json'
require 'digest/sha2'
require 'haml'
require 'sanitize'
require './spine'
require './tokens'

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
  haml :chatindex
end

post '/login/:topic' do |topic|
  topics[topic] = MongoChat.new(topic,db,key,iv) unless topics.has_key?(topic)
  
  username = Sanitize.clean(params[:name], Sanitize::Config::RESTRICTED)
  
  topics[topic].add({:message => 'I have arrived!', :from => username, :style => 'announces to', :user => nil }, {:raw => true})

  token = SecureToken.new(key,iv)
  token.payload = username
  cookies[:session] = token.to_e(true)
    
  haml :room, :locals => { :username => username, :topic => topic }
    
end

get '/chat/:topic' do |topic|
  topics[topic] = MongoChat.new(topic,db,key,iv) unless topics.has_key?(topic)
  
  username = topics[topic].user_from_request(request)
  
  haml :chattop, :locals => { :username => username, :topic => topic }
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
    
  stream :keep_open do |out|
    EventMachine::PeriodicTimer.new(20) { out << topics[topic].HEARTBEAT }
    topics[topic].connections << out
    out.callback { topics[topic].connections.delete(out) }
  end

end

post '/publish/:topic' do |topic|
  # TODO: Hook in authentication requirement here
  
  message = Sanitize.clean(params[:message], Sanitize::Config::RELAXED)
  style = Sanitize.clean(params[:style], Sanitize::Config::RESTRICTED)
  toUser = Sanitize.clean(params[:to], Sanitize::Config::RESTRICTED)
  toUser = nil if toUser == 'EVERYONE' or toUser == 'all'
   
  # Instantiate the room in this instance if needed
  topics[topic]  = MongoChat.new(topic,db,key,iv) unless topics.has_key?(topic)

  username = topics[topic].user_from_request(request)
  topics[topic].add({:message => message, :from => username, :style => style, :user => toUser }, {:raw => true})
  
  # Carry on
  haml :chattop, :locals => { :username => username, :topic => topic }
  
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
  
