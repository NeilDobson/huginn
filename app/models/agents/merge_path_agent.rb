module Agents
  class MergePathAgent < Agent
    can_dry_run!
    cannot_be_scheduled!

    description do
      <<-MD
	Process two walk events which match on their date.  The first is stored in memory until the second is available.
	For each point in the snapped track, output the snapped points if they are within tolerance of the simplified points, otherwise 
	use the simplified points.
	Incoming events look like
	  { "walk" => { "state" => "simplified", "count" => 2, "date" => 161818 =, "points" => [ { "lat" => 1, "lng" => 1 }, { "lat" => 2, "lng" => 2 } ] } }
	  { "walk" => { "state" => "snapped", "count" => 2, "date" => 161818 =, "points" => [ { "lat" => 1, "lng" => 1 }, { "lat" => 2, "lng" => 2 } ] } }
      MD
    end

    event_description do
      <<-MD
	  { "walk" => { "state" => "merged", "count" => 2, "date" => 161818 =, "points" => [ { "lat" => 1, "lng" => 1 }, { "lat" => 2, "lng" => 2 } ] } }
      MD
    end

    def default_options
	    { "tolerance" => 0.0005,
              "pathType1" => "simplified",
	      "pathType2" => "snapped",
              "expected_receive_period_in_days" => 3 }
    end


    def working?
      event_created_within?(interpolated['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
      memory['events'] ||= {}
      memory['events'][interpolated['pathType1']] ||= {}
      memory['events'][interpolated['pathType2']] ||= {}
      incoming_events.each { |e| 
        begin
	  state = e.payload['walk']['state']
	  date = e.payload['walk']['date']
	  matched = nil
	  simplified = nil
	  if (interpolated['pathType1'] == state) 
	    simplified = e.payload
	    memory['events'][state][date] = simplified
	    snapped = memory['events'][interpolated['pathType2']][date]
	    log("Found simplified for #{date} - snapped is #{snapped != nil}")
	  end
	  if (interpolated['pathType2'] == state) 
	    snapped = e.payload
	    memory['events'][state][date] = snapped
	    simplified = memory['events'][interpolated['pathType1']][date]
	    log("Found snapped for #{date} - simplified is #{snapped != nil}")
	  end
	  if ((simplified != nil) && (snapped != nil))
	    log("Merging events")
	    memory['events'][interpolated['pathType1']].delete(date)
	    memory['events'][interpolated['pathType2']].delete(date)
            merged = merge(simplified,snapped)
	    create_event(payload: merged)
	    log("Merged simplified and snapped")
	  end
	rescue => ex
	  log(ex)
	  log(ex.backtrace)
	  raise
	end
      }
   end

    def merge(simplifiedWalk,snappedWalk)
	merged = []
        simplified = simplifiedWalk["walk"]["points"]
        snapped = snappedWalk["walk"]["points"]
        
	interpStart = -1
	for index in 0 .. (snapped.length-1) do
  		if snapped[index].key?("originalIndex")
    			simplifiedElem = simplified[snapped[index]["originalIndex"]]
			#log(snapped[index])
			#log(simplifiedElem)
    			separation = Point.new(snapped[index]["lat"],snapped[index]["lng"]).separation(Point.new(simplifiedElem["lat"], simplifiedElem["lng"]))
    			if (separation < 0.00035)
      				if interpStart > 0
        				for extra in interpStart..index-1 do
          					merged.push({ "lat": snapped[extra]["lat"], "lng": snapped[extra]["lng"]})
        				end
      				end
      				merged.push({ "lat": snapped[index]["lat"], "lng": snapped[index]["lng"]})
      				interpStart = index+1
    			else
      				merged.push({ "lat": simplified[snapped[index]["originalIndex"]]["lat"], "lng": simplified[snapped[index]["originalIndex"]]["lng"] })
      				interpStart = -1
    			end
  		end
	end

        result = {}
        result['walk'] = snappedWalk["walk"].dup
	result['walk']['count'] = merged.length
        result['walk']['points'] = merged
	result['walk']['state'] = "merged"
 	return result
    end


  class Point
    def initialize(lat,lng)
      @lat = lat
      @lng = lng
    end
    def lat
      @lat
    end
    def lng
      @lng
    end
    def to_s
      "(#{@lat}, #{@lng})"
    end
    def inspect
      "Point(#{@lat}, #{@lng})"
    end
      
    def separation(p)
      return Math.sqrt(((self.lat - p.lat)**2) + ((self.lng - p.lng)**2))
    end
  end

  end
end
