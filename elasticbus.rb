#!/usr/bin/env ruby

# gem install sinatra sinatra-contrib thin bson_ext mongodb

require 'sinatra'
require 'sinatra/streaming'
require 'sinatra/cookies'
require 'mongo'
require 'json'
require 'digest/sha2'
require './spine'
require './tokens'
include Mongo # Import mongo symbols for convenience

configure do
  set :server, :thin
end

iv =  Digest::SHA2.new(256).digest("FBDfsdfrvyh8i67u5R^V$qc34x123e1w4rcq$Wtaw4twyj")
key = Digest::SHA2.new(256).digest("asasjhsdfFERt45y4hg3$&kjgfgf$Wsdcvbtymkhl8*r6t")

db = MongoClient.new("localhost", 27017).db("elasticbus")

topics = Hash.new
topics["general"] = MongoTopic.new("general",db) # Make sure we always have our base channel
topics["registrations"] = MongoTopic.new("registrations",db)

  # TODO: Rethink broadcasts
def broadcast(topics,message)
  topics.keys.each do |topic|
    topics[topic].add("event: broadcast\ndata: #{message}\n\n")
  end
end

def blast(topics,topic,message)
  topics[topic] = MongoTopic.new(topic,db) unless topics.has_key?(topic)
  topics[topic].add(message)
end

get '/' do
  "<center>I feel sorry for people who don't drink.<br> 
  When they wake up in the morning,<br> 
  that's as good as they're going to feel all day.<br>
  <br>
  -- Frank Sinatra<br></center>"
end

get '/register/:name' do |name|
  coll = db.collection("registrations")
  
  reg = { "name" => name }

  coll.update({"name" => name}, reg, { :upsert => true })
  topics["registrations"].add(name) if topics.has_key?("registrations")
    
  tokens = SecureToken.new(key,iv)
  tokens.payload = name
  cookies[:session] = tokens.to_e(true)
    
  "You registered '#{name}'"
end

get '/register/:type/:name' do |type,name|
  coll = db.collection(type + "_registrations")
  
  reg = { "name" => name }

  coll.update({"name" => name}, reg, { :upsert => true })
  topics["registrations"].add("#{type} #{name}") if topics.has_key?("registrations")
    
  tokens = SecureToken.new(key,iv)
  tokens.payload = "#{type}:#{name}"
  cookies[:session] = tokens.to_e(true)
    
  "You registered a '#{type}' called '#{name}'"
end

get '/register' do
  'Register what?'
end

get '/registrations' do
  coll = db.collection("registrations")
  
  names = []
  coll.find.each { |row|
    name = row["name"]
    names.push(name)
  }
  
  if names.empty?
    "No registrations"
  else
    "Registrations: " + names.join(', ')
  end
  
end

get '/registrations/:type' do |type|
  coll = db.collection(type + "_registrations")
  
  names = []
  coll.find.each { |row| 
    name = row["name"]
    names.push(name)
  }
    
  if names.empty?
    "No registrations"
  else
    "Registrations: " + names.join(', ')
  end
  
end

get '/subscribe/:topic/:epoch_stamp', :provides => 'text/event-stream' do |topic,epoch|
  topics[topic] = MongoTopic.new(topic,db) unless topics.has_key?(topic)
   
  stream :keep_open do |out|
    # Dump all of the historical
    topics[topic].read("since:#{epoch}").each do |message|
      out << topics[topic].format_message(message)
    end 
    
    # Carry on
    EventMachine::PeriodicTimer.new(20) { out << HEARTBEAT }
    topics[topic].connections << out
    out.callback { topics[topic].connections.delete(out) }
  end

end

get '/auth/set/:secret' do |secret|
  tokens = SecureToken.new(key,iv)
  tokens.payload = secret
  cookies[:session] = tokens.to_e(true)
  204
end

get '/auth/check/:secret' do |secret|
  return 400, "No token" unless cookies.has_key?(:session)
  tokens = SecureToken.new(key,iv)
  tokens.from_token(cookies[:session],true)
  
  unless tokens.verify(secret,60*60)
    return 401, "Unauthorized"
  else
    "OK: #{secret}"
  end
end

get '/subscribe/:topic', :provides => 'text/event-stream' do |topic|
  topics[topic] = MongoTopic.new(topic,db) unless topics.has_key?(topic)
    
  stream :keep_open do |out|
    EventMachine::PeriodicTimer.new(20) { out << topics[topic].HEARTBEAT }
    topics[topic].connections << out
    out.callback { topics[topic].connections.delete(out) }
  end

end

get '/topics' do
  
  topics["general"].topics.join(', ')
 
end

# Should be POST or LINK
get '/publish/:topic/:message' do |topic,message|
  topics[topic] = MongoTopic.new(topic,db) unless topics.has_key?(topic)
  topics[topic].add(message)
  # Bodiless ok
  204
end

# Should be POST or LINK
get '/broadcast/:message' do |message|
  broadcast(topics,message)
  
  "message received"
end

=begin
options '/' do
  status 200
  headers "Allow" => "LINK, UNLINK, POST, GET"
end

link '/' do
  #.. affiliate something ..
end

unlink '/' do
  #.. separate something ..
end
=end
  


