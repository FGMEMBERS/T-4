# T-4 electrical system.

var UPDATE_PERIOD = 0.2;

var update = func() {
  # This is just for temporal
  var volt = getprop("systems/electrical/outputs/adf");
  setprop("systems/electrical/outputs/adi", volt);
  setprop("/instrumentation/attitude-indicator/spin", volt/30);
  settimer(func { update(); }, UPDATE_PERIOD);
}

var init = func() {
  update();
}

setlistener("/sim/signals/fdm-initialized", func { init() });

