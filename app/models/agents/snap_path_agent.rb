module Agents
  class SnapPathAgent < Agent
    can_dry_run!
    cannot_be_scheduled!

    description do
      <<-MD
	Process an event containing latitude, longitude pairs with the Google snap to road service
	Incoming events look like
	  { "walk" => { "count" => 2, "date" => 161818 =, "points" => [ { "lat" => 1, "lng" => 1 }, { "lat" => 2, "lng" => 2 } ] } }
      MD
    end

    event_description do
      <<-MD
	  { "walk" => { "count" => 2, "date" => 161818 =, "points" => [ { "lat" => 1, "lng" => 1 }, { "lat" => 2, "lng" => 2 } ] } }
      MD
    end

    def default_options
	    { "pathType" => "simplified",
              "expected_receive_period_in_days" => 3 }
    end


    def working?
      event_created_within?(interpolated['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
	    incoming_events.each { |e| 
		    begin
			    log(e.payload)
			    walk = e.payload
			    if walk["walk"]["state"] == interpolated['pathType']
			      snapped = snapToRoad(walk)
			      create_event(payload: snapped)
			      log("Created a snapped path")
			    end
	    	rescue => ex
		  log(ex)
		  log(ex.backtrace)
		  raise
		end
	    }
    end

    def snapToRoad(walk) 
        points = walk["walk"]["points"] 
        toSnap = points.dup
	base = 0
	group = toSnap.shift(80)
	snapped = []
        googleKey = credential("googleMapsAPI")
	while (group.length() > 0) do
  		path = ""
  		#print("#{group.length()} points\n")
  		for i in 1..(group.length())
    			path += "#{group[i-1]["lat"]},#{group[i-1]["lng"]}|"
  		end
		log("Fetching snapped points")
  		url = URI("https://roads.googleapis.com/v1/snapToRoads?interpolate=true&key=#{googleKey}&path=#{path[0..-2]}")
  		reply = Net::HTTP.get(url)
  		section = JSON.parse(reply)
  		section["snappedPoints"].each { |e| if e.key?("originalIndex")
  							e["originalIndex"] = e["originalIndex"] + base
  						   end}
  		snapped += section["snappedPoints"]
  		base += group.length()
  		group = toSnap.shift(80)
	end
        result = {}
        result["walk"] = walk["walk"].dup 
        result['walk']['points'] = snapped.collect { |e| hash = { "lat": e["location"]["latitude"], "lng": e["location"]["longitude"] }
                                                         if (e.key?("originalIndex"))
             				      	           hash["originalIndex"] = e["originalIndex"]
                                                         end 
	                                                 hash }
        result['walk']['count'] = snapped.length
        result['walk']['state'] = "snapped"
        return result
      end
  end
end
