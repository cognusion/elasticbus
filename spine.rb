#!/usr/bin/env ruby

require 'mongo'
require 'bson'
require 'json'

include Mongo # Import mongo symbols for convenience

class Topic
  attr_accessor :name, :history, :last_updated, :count

  def initialize(name, time = nil, history = nil)
    @name = name
    @history = Array.new
    @history.push(history) unless history.nil?
    @last_updated = time.nil? ? Time.now : time 
    @count = @history.count
    
  end

  # Add an entry
  def add(entry, options = nil)
    @history.push(entry)
    @count += 1
  end
  
  # Read entries. 
  # Passing options e.g. 
  # { :limit => 6 } will only read the first 6
  def read(options = {})
    
    messages = Array.new()
    
    limit  = options[:limit]  || nil
    
    if limit.nil?
      # All of it
      return @history
    else
      # Some of it
      @history.each do |item|
        limit -= 1 unless limit.nil?
        messages.push(item)
        break if limit == 0
      end
      return messages
    end
  end
  
end

class MongoTopic < Topic
 
  attr_accessor :connections, :HEARTBEAT
  
  #override Topic
  def initialize(name, db)
    super(name)
    
    @db = db
    
    if @db.collections_info(name + "_topic").has_next? and @db.collection(name + "_topic").capped?
      # Exists, and is capped, we're good
      @coll = @db.collection(name + "_topic")
    else
      # Doesn't exist, or isn't capped
      @db.drop_collection(name + "_topic")
      @coll = @db.create_collection(name + "_topic", :capped => true, :size => 20*(1024**2), :max => 100 )
    end
    
    @connections = Array.new
    @HEARTBEAT = "\0"
    self.refresh
    
    ObjectSpace.define_finalizer(self, proc { @coll = nil; @connections=nil; @db=nil } )
  end
  
  # Returns array of connected users
  def connected
    users = Array.new
    @connections.each do |out| 
      # TODO: something standard
    end
    return users
  end
  
  # Returns boolean if anyone is connected
  def connected?
    !!@connections.count
  end
  
  # Returns an array of topics
  def topics
    colls = @db.collection_names
    topics = Array.new
    colls.each do |coll|
      coll.match(/^(.*)_topic$/) do |topic|
        topics.push(topic[1])
      end
    end
    return topics
  end
  
  # Formats an SSE message
  def format_message(message, event = false)
    message = "data: #{message}\n\n"
    message = "event: #{event}\n#{message}" if event
    return message
  end

  # Sends a message to all connections
  def notify(message)
    @connections.each { |out| out << self.format_message(message) }
  end
  
  # Refresh entries. 
  # Passing options e.g. 
  # { :notify_connections => true } will notify all connections of new messages
  # Options are also passed to read()
  def refresh(options = { :notify_connections => false })
    
    notify_connections = options[:notify_connections]
      
    # Mangle options to pass to read
    read_options = options
    read_options.delete(:notify_connections)
   
    if notify_connections
      # They want us to tell the >= 1 connections
      #puts "OLD:\n" + @history.join("\n") + "/OLD\n"
      new_history=self.read(read_options)
      #puts "NEW:\n" + new_history.join("\n") + "/NEW\n"
      hist_diff=new_history-@history
      #puts "DIFF:\n" + hist_diff.join("\n") + "/DIFF\n"
      hist_diff.each do |entry|
        self.notify(entry) #  Notify needs to be user aware, if applicable
      end
      @history=new_history
      @count = @history.count
    else
      # Speedy
      @history = self.read(read_options)
      @count = @history.count
    end
  end
  
  #override Topic
  def add(entry, options = {})
    doc = Hash.new
    refresh_options = options
    refresh_options[:notify_connections] = true
    if(options.has_key?(:raw) and options[:raw] == true) 
      doc = entry
    else
      doc['m'] = entry
    end
    @coll.insert(doc)
    @last_updated = Time.now
    self.refresh(refresh_options)
  end
  
  #override Topic
  def read(options = {})
    messages = Array.new
    
    filter = options[:filter] || nil
    limit  = options[:limit]  || nil
    raw    = options[:raw]    || nil
    
    if filter.nil?
      # All of it
      
      @coll.find.each { |row| 
        limit -= 1 unless limit.nil?
        if raw
          messages.push(row)
        else 
          messages.push(row["m"]) if row.has_key?("m")
        end
        break if limit == 0
      }
    elsif filter.match(/^since:\d+$/)
      # All of it since the epoch date specified
      
      filter.match(/^since:(\d+)$/) do |epoch|
      time = Time.at(epoch[1].to_i)
      time_id = BSON::ObjectId.from_time(time,{ :unique => false })
      @coll.find({'_id' => {'$gt' => time_id}}).each { |row|
        limit -= 1 unless limit.nil?
        if raw
          messages.push(row)
        else 
          messages.push(row["m"]) if row.has_key?("m")
        end
        break if limit == 0
      }
      end
    else
      # Filter
      
      # TODO: Intuitive filtering
      @coll.find(filter).each { |row| 
        limit -= 1 unless limit.nil?
        if raw
          messages.push(row)
        else 
          messages.push(row["m"]) if row.has_key?("m")
        end
        break if limit == 0
      }
    end
    return messages
  end
end

class MongoChat < MongoTopic

  #override MongoTopic
  def initialize(room, db, key, iv)
    super(room,db)
    
    @key = key
    @iv = iv
    @HEARTBEAT = "<!-- OK -->\n"
    @history = self.read({:raw => true })
    
  end
  
  #override MongoTopic
  # TODO: Needs to be cluster-aware
  def connected
    users = Array.new
    @connections.each do |out| 
      users.push(self.user_from_connection(out))
    end
    return users
  end
  
  # Return the username, given the connection
  def user_from_connection(connection)
    cookie = connection.instance_variable_get(:@app).request.cookies['session']
    t = SecureToken.new(@key,@iv)
    t.from_token(cookie,true)
    return t.payload.split(':',2)[0]
  end

  # Return the username, given the request
  def user_from_request(request)
    cookie = request.cookies['session']
    t = SecureToken.new(@key,@iv)
    t.from_token(cookie,true)
    return t.payload.split(':',2)[0]
  end
  
  # Return the disaplyname, given the request
  def displayuser_from_request(request)
    cookie = request.cookies['session']
    t = SecureToken.new(@key,@iv)
    t.from_token(cookie,true)
    return t.payload.split(':',2)[1]
  end
    
  #override MongoTopic
  # Notify's users on this instance if a message is broadcast, from them, or to them.
  def notify(message)
    
    @connections.each do |out|
        out << self.format_message(message) if self.to_me?(message,out) or self.from_me?(message,out)
    end
    
  end
  
  # Return boolean if the specified message is a broadcast, or to the specificed connection
  def to_me?(message,connection)
    if(!message.has_key?('user') or message['user'].nil? or message['user'] == 'all')
      return true
    else 
      # Unicast
      this_user = self.user_from_connection(connection)
      return true if this_user == message['user']   
      return false
    end
  end
  
  # Return boolean if the specified message was from the specificed connection
  def from_me?(message,connection)
    this_user = self.user_from_connection(connection)
    return true if this_user == message['from']   
    return false
  end
  
  
  #override MongoTopic
  # Formats an entry with approporiate HTML trimmings
  def format_message(entry)
    return if entry.nil?
    # Assumes all variables properly 
    # Sanitized before passing!!!
    message = entry['message'] || "empty"
    from    = entry['fromDisplay']
    style   = entry['style']
    user    = entry['user'] if entry.has_key?('user') || nil
    stamp   = entry['_id'].generation_time.strftime "%H:%M:%S"
    # user = nil goes to all subscribers
    prefix = "<p><b>(#{stamp}) #{from} #{style}"
    prefix += " Everyone" if user.nil?
    prefix += " #{user}" unless user.nil?
    prefix += "</b>:  "
      
    suffix = "</p>"

    return prefix + message + suffix
  end
  
end
