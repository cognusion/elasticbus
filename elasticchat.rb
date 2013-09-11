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

room = "test"
unless ARGV.empty?
  room = ARGV.shift
end

topics = Hash.new
topics["test"] = MongoChat.new("test",db,key,iv) # Make sure we always have our base channel
  
get '/' do
  haml :chatindex, :locals => { :topic => room }
end

post '/login/:topic' do |topic|
  topics[topic] = MongoChat.new(topic,db,key,iv) unless topics.has_key?(topic)
  
  username = Sanitize.clean(params[:name], Sanitize::Config::RESTRICTED)
  avatar = Sanitize.clean(params[:avatar], Sanitize::Config::RESTRICTED)
  avatar = nil unless avatar.nil? or avatar.size > 2
    
  displayname = '<font color="#';
  3.times do 
    displayname += rand(1..255).to_s(16)
  end
  displayname += '">' + username + '</font>'
  
  displayname = '<img src="' + avatar + '">  ' + displayname unless avatar.nil?
  
  topics[topic].add({:message => 'I have arrived!', :fromDisplay => displayname, :from => username, :style => 'announces to', :user => nil }, {:raw => true})

  token = SecureToken.new(key,iv)
  token.payload = username + ':' + displayname
  cookies[:session] = token.to_e(true)
    
  haml :room, :locals => { :username => username, :topic => topic }
    
end

get '/chat/:topic' do |topic|
  topics[topic] = MongoChat.new(topic,db,key,iv) unless topics.has_key?(topic)
  
  username = topics[topic].user_from_request(request)
  
  # Build the array of users we can send to
  usernames = topics[topic].connected
  usernames.unshift('EVERYONE')

  haml :chattop, :locals => { :username => username, :topic => topic, :lastuser => 'EVERYONE', :usernames => usernames }
end

get '/subscribe/:topic/:epoch_stamp', :provides => 'text/html' do |topic,epoch|
  topics[topic] = MongoChat.new(topic,db,key,iv) unless topics.has_key?(topic)
   
  stream :keep_open do |out|
    # Dump all of the historical
    topics[topic].read({ :filter => "since:#{epoch}", :raw => true }).each do |message|
      out << topics[topic].format_message(message) if topics[topic].to_me?(message,out) or topics[topic].from_me?(message,out)
    end 
    
    # Carry on
    cardio = EventMachine::PeriodicTimer.new(20) do
      begin
        out << topics[topic].HEARTBEAT
      rescue
        cardio.cancel
      end
    end
    
    topics[topic].connections << out
    
    out.callback do
      topics[topic].connections.delete(out)
      cardio.cancel
    end
  end

end

get '/subscribe/:topic', :provides => 'text/html' do |topic|
  topics[topic] = MongoChat.new(topic,db,key,iv) unless topics.has_key?(topic)
    
  stream :keep_open do |out|
    cardio = EventMachine::PeriodicTimer.new(20) do
      begin
        out << topics[topic].HEARTBEAT
      rescue
        cardio.cancel
      end
    end
    
    topics[topic].connections << out
    
    out.callback do
      topics[topic].connections.delete(out)
      cardio.cancel
    end
  end

end

post '/publish/:topic' do |topic|
  # TODO: Hook in authentication requirement here
  
  message = Sanitize.clean(params[:message], Sanitize::Config::RELAXED)
  style = Sanitize.clean(params[:style], Sanitize::Config::RESTRICTED)
  user = Sanitize.clean(params[:to], Sanitize::Config::RESTRICTED)
  if user == 'EVERYONE' or user == 'all'
    toUser = nil
  else
    toUser = user
  end
   
  # Instantiate the room in this instance if needed
  topics[topic]  = MongoChat.new(topic,db,key,iv) unless topics.has_key?(topic)

  username = topics[topic].user_from_request(request)
  displayname = topics[topic].displayuser_from_request(request)

  unless message.size < 2
    topics[topic].add({:message => message, :fromDisplay => displayname, :from => username, :style => style, :user => toUser }, {:raw => true})
  end

  # Build the array of users we can send to
  usernames = topics[topic].connected
  usernames.unshift('EVERYONE')
  
  # Carry on
  haml :chattop, :locals => { :username => username, :topic => topic, :lastuser => user, :usernames => usernames }
  
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
  
