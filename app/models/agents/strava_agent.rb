module Agents
  require "net/http"
  require "uri"

  class StravaAgent < Agent
    cannot_be_scheduled!
    cannot_receive_events!

    description do <<-MD
      The Strava Agent will be the target of a Strava notification, allowing registration & responding to activity notifications. 
      The target of the notification is 

      ```
         https://#{ENV['DOMAIN']}/users/#{user.id}/strava/#{id || ':id'}/#{options['secret'] || ':secret'}
      ```

      #{'The placeholder symbols above will be replaced by their values once the agent is saved.' unless id}

      Options:

        * `secret` - A token that the host will provide for authentication.
        * `expected_receive_period_in_days` - How often you expect to receive
          events this way. Used to determine if the agent is working.
      MD
    end

    event_description do
      <<-MD
	The details of a recent activity, including GPX coordinates.
      MD
    end

    def default_options
      { "secret" => "supersecretstring",
        "expected_receive_period_in_days" => 1
      }
    end

    def receive_web_request(request)
      # check the secret
      secret = request.path_parameters[:secret]
      return ["Not Authorized", 401] unless secret == interpolated['secret']

      params = request.query_parameters.dup
      begin
        params.update(request.request_parameters)
      rescue EOFError
      end

      # push dot separated parameters into hash structures
      block = -> (hash,key,value) {
                   parts = key.split('.',2)
                   if parts.size == 2
                     if not hash.key?(parts[0])
                       subHash = Hash.new
                       hash[parts[0]] = subHash
                     else
                       subHash = hash[parts[0]]
                     end
                     block.call(subHash, parts[1], value)
                   else
                     hash[key] = value
                   end
                 }

     params.keys.each { | k |
       block.call(interpolation_context, k, params[k]) }


      method = request.method_symbol.to_s
      if method == 'get' 
	log("Accepting a get request to register a webhook")
	challenge = params['hub.challenge']
        return [ "{ \"hub.challenge\": \"#{challenge}\" }\n", 200, 'application/json' ]
      end

      log("Accepting a post request with activity data")
      notification = JSON.parse(request.raw_post())
      if notification['aspect_type'] != 'create' 
        return [ "", 200, 'application/json' ]
      end
      if notification['object_type'] != 'activity' 
        return [ "", 200, 'application/json' ]
      end

      details = fetch_details(notification['object_id'],Time.at(notification['event_time']).strftime("%Y_%m_%d"),get_access_token())
    end

    def fetch_details(id,event_time,token)
       params =  { "keys" => "latlng", "key_by_type" => 'true' }
       log("fetch_details params = #{params}")
	    con = Faraday.new(url: 'https://www.strava.com', params: params, headers: { 'Authorization' => "Bearer #{token}" })
	    url = "/api/v3/activities/#{id}/streams"
	    log("url is #{url}")
	    res = con.get url
	    log("response is #{res.body}")
	    begin
	      gpx = JSON.parse(res.body)
	      latlng = gpx['latlng']['data'].collect { |each| { "lat" => each[0], "lng" => each[1] } }
	      log("Creating event")
	      create_event(payload: { "walk" => { "state" => "raw", "date" => event_time.to_s , "count" => latlng.length, "points" => latlng }})
	    rescue => ex
		    log("Event creation failed - #{ex}")
	      gpx = {}
	    end
	end


    def get_access_token()
	    log('getting token')
	    currentToken = JSON.parse(credential('STRAVA_TOKEN'))
	    log("expires at - #{currentToken['expires_at']}, now - #{Time.now.to_i + 600}")
	    if ((currentToken['expires_at']) > (Time.now.to_i + 600))
		    log("re-using token #{currentToken['access_token']}")
		    return currentToken['access_token']
		end
	    log("Trying to refresh the token")
	    secret = JSON.parse(credential('STRAVA_SECRET'))
	    params =  {"client_id" => secret['client_id'], "client_secret" => secret['client_secret'],
	               "grant_type" => 'refresh_token', 'refresh_token' => currentToken['refresh_token']}
	    log("params = #{params}")
	    con = Faraday.new 'https://www.strava.com'
	    res = con.post '/api/v3/oauth/token', params
	    log("response is #{res.body}")
	    begin
	      newToken = JSON.parse(res.body)
	    rescue
		newToken = {}
	    end
	    if newToken['access_token'].present?
	      log('Token refreshed')
	      set_credential('STRAVA_TOKEN',res.body)
	      return newToken['access_token']
	    else
	      log('Token not refreshed')
	    end
	    return ''
    end

    def set_credential(name, value)
      c = user.user_credentials.find_or_initialize_by(credential_name: name)
      c.credential_value = value
      c.save!
    end

    def working?
      event_created_within?(interpolated['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def validate_options
      unless options['secret'].present?
        errors.add(:base, "Must specify a secret for 'Authenticating' requests")
      end

    end

    def payload_for(params)
	    Utils.value_at(params, '.') || {}
    end
  end
end
