require 'handlersocket'

class HandlerSocket
  class HandlerSocketError < RuntimeError; end
  
  #TODO handlersocket ruby binding has no socket error exception
  #use a temp solution here, need to improve binding
  def open_index_with_error(*args)
    result = open_index(*args)
    if result[0] == -1
      raise HandlerSocketError, result[1]
    else
      result
    end
  end

  def execute_single_with_error(*args)
    result = execute_single(*args)
    if result[0] == -1
      raise HandlerSocketError, result[1]
    else
      result
    end
  end
end

class ActiveRecord::Base
  def self.use_handlersocket(host = '127.0.0.1', port = 9998)
    @@hs = HandlerSocket.new(host, port, 5)
    @@hs_pk_index_ids = {}
    class << self
      alias_method_chain :find_one, :handlersocket
    end
  end

  class << self

    def find_one_with_handlersocket(id, options)
      retried = false
      begin
        db_name = connection.instance_variable_get(:@config)[:database]
        unless index_id = @@hs_pk_index_ids["#{db_name}.#{table_name}"]
          index_id = @@hs_pk_index_ids.size
          @@hs.open_index_with_error(index_id, db_name, table_name, 'PRIMARY', column_names.join(","))
          @@hs_pk_index_ids["#{db_name}.#{table_name}"] = index_id
        end

        result = @@hs.execute_single_with_error(index_id, '=', [id])
        result.shift
        if result.size == 0
          raise ActiveRecord::RecordNotFound, "Couldn't find #{name} with ID=#{id}"
        else
          instantiate(Hash[*column_names.zip(result).flatten])
        end
      rescue HandlerSocket::HandlerSocketError => e
        if !retried
          @@hs.reconnect
          @@hs_pk_index_ids = {}
          retried = true
          retry
        else
          raise e
        end
      end
    end

  end
end
