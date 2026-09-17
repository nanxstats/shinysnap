/* shinysnap: client-side script.
 *
 * Inventory half: keeps the server informed of which inputs are bound on the
 * page and which input binding each one uses, so that a snapshot describes
 * the UI as the user sees it (values of removed dynamic UI are dropped) and
 * so that the server can pick the right payload for each binding on restore.
 *
 * Plain ES2017, no build step. jQuery ($) is available because Shiny loads it.
 */
(function () {
  "use strict";

  var shinysnap = window.shinysnap || {};
  shinysnap.version = "0.1.0";
  shinysnap.debug = shinysnap.debug || false;
  shinysnap.adapters = shinysnap.adapters || {};
  shinysnap.registerAdapter = function (bindingName, fn) {
    shinysnap.adapters[bindingName] = fn;
  };
  window.shinysnap = shinysnap;

  function log() {
    if (shinysnap.debug && window.console && console.log) {
      console.log.apply(console, ["[shinysnap]"].concat([].slice.call(arguments)));
    }
  }

  // The name a binding was registered under ("shiny.sliderInput"). Some
  // packages register without a name; fall back to the input type the binding
  // reports for the element ("shinyMatrix.matrixNumeric"), then to "".
  function bindingName(binding, el) {
    if (binding.name) return binding.name;
    try {
      if (typeof binding.getType === "function") {
        var type = binding.getType(el);
        if (type) return type;
      }
    } catch (e) {
      /* fall through */
    }
    return "";
  }

  // Map of bound input id -> binding name, with keys in sorted order so that
  // two inventories with the same content serialize identically.
  function inventory() {
    var $ = window.jQuery;
    var found = {};
    var ids = [];
    var els = document.querySelectorAll(".shiny-bound-input");
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var binding = $(el).data("shiny-input-binding");
      if (!binding) continue;
      var id = binding.getId(el);
      if (!id) continue;
      if (!(id in found)) ids.push(id);
      found[id] = bindingName(binding, el);
    }
    ids.sort();
    var out = {};
    for (var j = 0; j < ids.length; j++) out[ids[j]] = found[ids[j]];
    return out;
  }
  shinysnap.inventory = inventory;

  var lastSent = null;
  var timer = null;

  function sendInventory() {
    var inv = inventory();
    var serialized = JSON.stringify(inv);
    if (serialized === lastSent) return;
    lastSent = serialized;
    window.Shiny.setInputValue(".shinysnap_inventory", inv);
    log("inventory", inv);
  }

  function scheduleInventory() {
    if (timer !== null) clearTimeout(timer);
    timer = setTimeout(function () {
      timer = null;
      sendInventory();
    }, 50);
  }

  function announce() {
    lastSent = null;
    sendInventory();
    window.Shiny.setInputValue(".shinysnap_ready", true, { priority: "event" });
    log("ready");
  }

  function install() {
    var $ = window.jQuery;
    $(document).on("shiny:bound shiny:unbound", function (evt) {
      if (evt.bindingType === "input") scheduleInventory();
    });
    // A (re)connect resets the server's view of the inputs: report again.
    $(document).on("shiny:connected", announce);
    var app = window.Shiny.shinyapp;
    if (app && typeof app.isConnected === "function" && app.isConnected()) {
      announce();
    }
  }

  // The script may load before Shiny (when included in the UI head) or after
  // it (when injected by the server); wait until both jQuery and Shiny exist.
  function whenShinyReady(fn, tries) {
    if (window.jQuery && window.Shiny) {
      fn();
      return;
    }
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () {
        whenShinyReady(fn, 0);
      });
      return;
    }
    tries = tries || 0;
    if (tries < 200) setTimeout(function () { whenShinyReady(fn, tries + 1); }, 50);
  }

  whenShinyReady(install, 0);
})();
