###############################################################################
# advroutemgr.nas by Tatsuhiro Nishioka
# - Advanced Route Manager 
#   This is a helper script for the standard Route Manager that
#   automatically removes the first way point prior to reaching it for maintaining
#   the heading direction after the turn.
#
# How to use:
#  Just add this script to -set.xml file. It is automatically engaged
#  and disengaged by monitoring waypoints and heading lock status.
# 
# Copyright (C) 2009 Tatsuhiro Nishioka (tat dot fgmacosx at gmail dot com)
# This file is licensed under the GPL version 2 or later.
# 
###############################################################################

#
# In case Nasal doesn't have math.tan (doesn't in 1.9.1)
#
var tan = func(angle) { return math.sin(angle) / math.cos(angle); };

var AdvancedRouteManager = { _instance : nil };
AdvancedRouteManager.instance = func()
{
  if (AdvancedRouteManager._instance == nil) {
    AdvancedRouteManager._instance = { parents : [AdvancedRouteManager], isRunning : 0 };
  }
  return AdvancedRouteManager._instance;
  
}

#
# heading : calculates heading from pos1 to pos2
# 
#
AdvancedRouteManager.heading = func(pos1, pos2)
{ 
  var heading = 90 - (math.atan2(pos2.lat - pos1.lat, pos2.lon - pos1.lon) * 180 /  math.pi);
  if (heading < 0) {
    heading += 360; 
  } elsif (heading > 360) {
    heading -= 360;
  }
  return heading;
}

#
# getWaypointPosition : returns a hash containing
# latitude and longitude for a given waypoint indexd (0 <= id <= num waypoint -1 )
#
AdvancedRouteManager.getWaypointPosition = func(index)
{
  var aproot="/autopilot/route-manager/route/";
  return { lat : getprop(aproot ~ "wp[" ~ index ~ "]/latitude-deg"),
           lon : getprop(aproot ~ "wp[" ~ index ~ "]/longitude-deg") };
}

#
# distanceToWaypoint: returns the distance in nm to a given waypoint
# 0 <= index <= # waypoint - 1
#
AdvancedRouteManager.distanceToWaypoint = func(index)
{
  return getprop("/autopilot/route-manager/wp[" ~ index ~ "]/dist");
}

#
# distanceForRemoval: returns distance to the waypoint in nm
# for removing the current target waypoint. AdvancedRouteManager will
# remove the target waypoint when the distance for the waypoint
# reaches this value.
#
AdvancedRouteManager.distanceForRemoval = func() {
  # 2 waypoints are required for automatic waypoint removal
  # if there are less than 2 waypoints, no removal is required
  var wp_num = getprop("/autopilot/route-manager/route/num");
  if (wp_num < 2) {
    return 0;
  }
  var myPos = { lat : getprop("/position/latitude-deg"), 
                lon : getprop("/position/longitude-deg") };
  var wp1 = me.getWaypointPosition(0);
  var wp2 = me.getWaypointPosition(1);

  var heading1 = me.heading(myPos, wp1);
  var heading2 = me.heading(wp1, wp2);
  
  var angle = math.abs(heading2 - ((180 + heading1)));
  if (angle > 360) { angle -= 360; }
  if (angle > 180) { angle = 360 - angle; } 

  var velocity = getprop("/velocities/groundspeed-kt");
  # required radius (nm) for 2.5 deg / sec turn for 120 kt (3.0 deg - 0.5 deg for roll-in/out delay),
  # radius is multiplied by vel / 120 kt for error adjusting in higher speed
  var degps = getprop("/autopilot/advanced-route-manager/estimate-turn-rate-degps") * math.pi / 180;
  var radius = velocity / 3600 / degps * (velocity / 120);

  var distance = 0;
  if (angle > 0.1 and angle < 179.9) {
    distance = math.abs(radius / tan(angle * math.pi / 180 / 2));
  } 

  setprop("/autopilot/advanced-route-manager/heading1-deg", heading1);
  setprop("/autopilot/advanced-route-manager/heading2-deg", heading2);
  setprop("/autopilot/advanced-route-manager/angle-deg", angle);
  setprop("/autopilot/advanced-route-manager/turn-radius-nm", radius);
  setprop("/autopilot/advanced-route-manager/distance-for-removal-nm", distance);

  return distance;
}

#
# update: automatically removes the first waypoint
# for maintaining the heading degree after making a turn
#
AdvancedRouteManager.update = func() {
  # available only when true heading lock is engaged
  # and the number of waypoints is more than one.
  var wpNum = getprop("/autopilot/route-manager/route/num");
  if (getprop("/autopilot/locks/heading") == "true-heading-hold" and wpNum != nil and wpNum >= 2) {
    if (me.isRunning == 0) {
      screen.log.write("Activating Route Manager Helper.");
      me.isRunning = 1;
    }
    var dist = me.distanceToWaypoint(0);
    var dist4removal = me.distanceForRemoval();
    if (dist <= dist4removal) {
      setprop("/autopilot/route-manager/input", "@delete0");
    }
    setprop("/autopilot/advanced-route-manager/distance-before-removal-nm", dist - dist4removal);
    # set timer for the next iteration depending the "speed-up" value
    var interval = 1.0;
    interval /= getprop("/sim/speed-up");
    settimer(func { AdvancedRouteManager.instance().update(); }, interval);
  } else {
    me.isRunning = 0;
  }
}

AdvancedRouteManager.activate = func() {
  if (me.isRunning == 0) {
    me.update();
  }
}

#
# setConfiguration : writing per-aircraft configuration for auto-pilot
#
AdvancedRouteManager.setConfiguration = func(config) {
  props.globals.getNode("/autopilot/advanced-route-manager").setValues(config);
}

AdvancedRouteManager.initialize = func() {
  # setting default turn rate to 2.5 deg/sec (considering roll-in/out delay)
  setprop("/autopilot/advanced-route-manager/estimate-turn-rate-degps", 2.5);

  # This is for controlling speed, altitude, flap, and gear for full automatic flight
  # but the controller part is not implemented yet
  # A sample configuration (for MRJ)
  me.setConfiguration({ config : {
    'cruise-speed-kt'    : 285,
    'climb-speed-kt'     : 200,
    'climb-pitch-deg'    : 12,
    'descent-fps'        : -2000,
    'descent-speed-kt'   : 210,
    'max-flap-speed-kt'  : 200,
    'approach-dist-nm'   : 10,
    'approach-speed-kt'  : 150,
    'flap-config'        : { num : 3, step : [0.333, 0.667, 1.000], speed : [150, 135, 120]},
    'gear-down-speed-kt' : 150
  }});
}

setlistener("/autopilot/route-manager/route/num", func { AdvancedRouteManager.instance().activate(); });
setlistener("/autopilot/locks/heading", func { AdvancedRouteManager.instance().activate(); });
setlistener("/sim/signals/fdm-initialized", func { AdvancedRouteManager.instance().initialize(); });

