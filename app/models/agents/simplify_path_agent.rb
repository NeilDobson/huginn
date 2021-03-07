module Agents
  class SimplifyPathAgent < Agent
    can_dry_run!
    cannot_be_scheduled!

    description do
      <<-MD
	Process an event containing latitude, longitude pairs with the Douglas-Peuker algoritm to remove redundant points.
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
	    { "tolerance" => 0.0005,
              "pathType" => "raw",
              "expected_receive_period_in_days" => 3 }
    end


    def working?
      event_created_within?(interpolated['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
	    incoming_events.each { |e| 
		    begin
			    if e.payload["walk"]["state"] == interpolated["pathType"]
			      log(e.payload)
			      simplified = simplify(e.payload)
			      create_event(payload: simplified)
			    end
	    	rescue => ex
		  log(ex)
		  log(ex.backtrace)
		  raise
		end
	    }
    end

    def simplify(walk) 
	    simplified =  douglasPeucker(walk["walk"]["points"].collect { |e| Point.new(e['lat'], e['lng']) },0.00005,"").collect { |e| { "lat" => e.lat, "lng" => e.lng } }
            result = {}
            result["walk"] = walk["walk"].dup
            result['walk']['points'] = simplified
	    result['walk']['count'] = simplified.length
	    result['walk']['state'] = "simplified"
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

  class Line
    def initialize(p1,p2)
      @p1 = p1
      @p2 = p2
    end
    def p1
     @p1
    end
    def p2
      @p2
    end
  
    def distanceToPoint(p)
      #slope
      if (self.p2.lat == self.p1.lat)
        m = 99999
      else
        m = (self.p2.lng - self.p1.lng) / (self.p2.lat - self.p1.lat)
      end
  
      # y offset
      b = self.p1.lng - (m*self.p1.lat)
      d = []
      d.push((p.lng - (m*p.lat) - b).abs() / Math.sqrt((m**2)+1))
      d.push(Math.sqrt(((p.lat - self.p1.lat)**2) + ((p.lng - self.p1.lng)**2)))
      d.push(Math.sqrt(((p.lat - self.p2.lat)**2) + ((p.lng - self.p2.lng)**2)))
      val = d.collect { |e| e.abs() }.sort[0]
      #print("#{self.p1}, #{self.p2}, #{p}, #{m}, #{b}, #{d}, #{val}\n")
      return val
    end
  end

  def douglasPeucker(points, tolerance,text)
    #print("Checking #{text}, #{points.length} #{points[0]},#{points[-1]}\n")
    if (points.length <= 2)
      return points
    end

    line = Line.new(points[0], points[-1])
    maxDistance = 0
    maxDistanceIndex = 0
    for i in 0..points.length-1
      distance = line.distanceToPoint(points[i])
      if (distance > maxDistance)
        maxDistance = distance
        maxDistanceIndex = i
      end
    end
    #print("#{maxDistance} at #{maxDistanceIndex} for #{points[maxDistanceIndex]}\n")

    if (maxDistance > tolerance)
      part1 = points[0..maxDistanceIndex]
      part2 = points[maxDistanceIndex..-1]
      #print("#{part1[0]},#{part1[-1]},#{part1.length} -  #{part2[0]},#{part2[-1]},#{part2.length}\n")
      return douglasPeucker(part1,tolerance,"even") + douglasPeucker(part2,tolerance,"odd")
    else
      # nothing to keep
      #print("Nothing to keep - #{maxDistance}\n")
      #print "first and last"
      #print("Returning #{points[0]}, #{points[-1]}\n")
      return [points[0],points[-1]]
    end
  end
  end
end
