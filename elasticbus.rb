#!/usr/bin/env ruby

# gem install sinatra sinatra-contrib thin bson_ext mongodb

require 'sinatra'
require 'mongo'
require 'json'
require './spine'
include Mongo # Import mongo symbols for convenience

HEARTBEAT = "\0" #"<!-- OK -->\n"

configure do
  set :server, :thin
end

db = MongoClient.new("localhost", 27017).db("elasticbus")

topics = Hash.new
topics["general"] = MongoTopic.new("general",db) # Make sure we always have our base channel

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
  
def format_message(message, event = false)
  message = "data: #{message}\n\n"
  message = "event: #{event}\n#{message}" if event
  return message
end

get '/' do
  "<center>I feel sorry for people who don't drink.<br> 
  When they wake up in the morning,<br> 
  that's as good as they're going to feel all day.<br>
  <br>
  -- Frank Sinatra<br></center>"
end

=begin
get '/register/:name' do |name|
  coll = db.collection("registrations")
  
  reg = { "name" => name }

  coll.update({"name" => name}, reg, { :upsert => true })
  topics["registrations"].add(name) if topics.has_key?("registrations")
  "You registered '#{name}'"
end

get '/register/:type/:name' do |type,name|
  coll = db.collection(type + "_registrations")
  
  reg = { "name" => name }

  coll.update({"name" => name}, reg, { :upsert => true })
  topics["registrations"].add("#{type} #{name}") if topics.has_key?("registrations")
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
=end

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

get '/subscribe/:topic', :provides => 'text/event-stream' do |topic|
  topics[topic] = MongoTopic.new(topic,db) unless topics.has_key?(topic)
    
  stream :keep_open do |out|
    EventMachine::PeriodicTimer.new(20) { out << HEARTBEAT }
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
  


