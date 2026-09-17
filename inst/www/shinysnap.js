/* shinysnap: client-side script.
 *
 * Two halves:
 *
 * 1. Inventory. Keeps the server informed of which inputs are bound on the
 *    page and which input binding each one uses, so that a snapshot
 *    describes the UI as the user sees it and the server can pick the right
 *    payload per binding on restore.
 *
 * 2. Restore transactions. The server sends every value at once; values for
 *    inputs that are on the page are applied through the binding's
 *    receiveMessage(); the rest wait until their input is bound (dynamic UI
 *    that appears during the cascade), which is why no timing configuration
 *    is needed. The transaction settles after a quiet period and reports one
 *    status per input.
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

  function errorMessage(e) {
    if (e && e.message) return String(e.message);
    return String(e);
  }

  // ---------------------------------------------------------------- bindings

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

  function boundInputs() {
    var $ = window.jQuery;
    var out = [];
    var els = document.querySelectorAll(".shiny-bound-input");
    for (var i = 0; i < els.length; i++) {
      var binding = $(els[i]).data("shiny-input-binding");
      if (!binding) continue;
      var id = binding.getId(els[i]);
      if (!id) continue;
      out.push({ id: id, el: els[i], binding: binding });
    }
    return out;
  }

  // The bound element for an input id, or null. Most inputs carry the id on
  // the bound element; the scan covers bindings that use data-input-id.
  function findBound(id) {
    var $ = window.jQuery;
    var el = document.getElementById(id);
    if (el && el.classList.contains("shiny-bound-input")) {
      var binding = $(el).data("shiny-input-binding");
      if (binding && binding.getId(el) === id) return { el: el, binding: binding };
    }
    var all = boundInputs();
    for (var i = 0; i < all.length; i++) {
      if (all[i].id === id) return all[i];
    }
    return null;
  }

  // --------------------------------------------------------------- inventory

  // Map of bound input id -> binding name, with keys in sorted order so that
  // two inventories with the same content serialize identically.
  function inventory() {
    var found = {};
    var ids = [];
    var all = boundInputs();
    for (var i = 0; i < all.length; i++) {
      if (!(all[i].id in found)) ids.push(all[i].id);
      found[all[i].id] = bindingName(all[i].binding, all[i].el);
    }
    ids.sort();
    var out = {};
    for (var j = 0; j < ids.length; j++) out[ids[j]] = found[ids[j]];
    return out;
  }
  shinysnap.inventory = inventory;

  var lastSent = null;
  var inventoryTimer = null;

  function sendInventory() {
    var inv = inventory();
    var serialized = JSON.stringify(inv);
    if (serialized === lastSent) return;
    lastSent = serialized;
    window.Shiny.setInputValue(".shinysnap_inventory", inv);
    log("inventory", inv);
  }

  function scheduleInventory() {
    if (inventoryTimer !== null) clearTimeout(inventoryTimer);
    inventoryTimer = setTimeout(function () {
      inventoryTimer = null;
      sendInventory();
    }, 50);
  }

  function announce() {
    lastSent = null;
    sendInventory();
    window.Shiny.setInputValue(".shinysnap_ready", true, { priority: "event" });
    log("ready");
  }

  // ----------------------------------------------------------- comparisons

  // Normalize a value for comparison: scalar and 1-array are equal, null and
  // [] are equal, object keys are sorted.
  function normalize(x) {
    if (x === undefined || x === null) return null;
    if (Array.isArray(x)) {
      if (x.length === 0) return null;
      if (x.length === 1) return normalize(x[0]);
      return x.map(normalize);
    }
    if (typeof x === "object") {
      var keys = Object.keys(x).sort();
      var out = {};
      for (var i = 0; i < keys.length; i++) out[keys[i]] = normalize(x[keys[i]]);
      return out;
    }
    return x;
  }

  function same(a, b) {
    return JSON.stringify(normalize(a)) === JSON.stringify(normalize(b));
  }

  function currentValue(binding, el) {
    try {
      return binding.getValue(el);
    } catch (e) {
      return undefined;
    }
  }

  // ------------------------------------------------------------ transaction

  var txn = null;

  function touch(t) {
    if (t) t.lastActivity = Date.now();
  }

  function record(t, id, status, binding, detail) {
    t.results[id] = { id: id, status: status, binding: binding || "", detail: detail || "" };
    touch(t);
    log("restore", t.id, id, status, detail || "");
  }

  function clearTransaction() {
    if (txn === null) return;
    if (txn.timer !== null) clearTimeout(txn.timer);
    txn.timer = null;
    txn = null;
  }

  // Apply one record now. Applies are serialized through a promise chain so
  // that receiveMessage() calls never interleave.
  function enqueueApply(t, id, reason) {
    t.inflight += 1;
    t.chain = t.chain
      .then(function () {
        if (txn !== t) return undefined;
        return applyOne(t, id, reason);
      })
      .catch(function (e) {
        record(t, id, "failed", "", errorMessage(e));
      })
      .then(function () {
        t.inflight -= 1;
        touch(t);
      });
  }

  async function applyOne(t, id, reason) {
    var $ = window.jQuery;
    var rec = t.records[id];
    var found = findBound(id);
    if (!found) return; // not bound any more; stays pending
    var el = found.el;
    var binding = found.binding;
    var name = bindingName(binding, el);
    var message = rec.message;
    var hasExpect = Object.prototype.hasOwnProperty.call(rec, "expect");

    // An element that appeared during the restore may already carry the
    // value, because the server built it with restoreInput(); do not touch it.
    if (reason === "bound" && hasExpect && same(currentValue(binding, el), rec.expect)) {
      record(t, id, "constructed", name, "");
      t.applied[id] = true;
      return;
    }

    var adapter = shinysnap.adapters[name];
    if (typeof adapter === "function") {
      try {
        message = adapter(message, el, binding, rec);
      } catch (e) {
        record(t, id, "failed", name, "adapter: " + errorMessage(e));
        return;
      }
      if (message === null || message === undefined) {
        record(t, id, "skipped", name, "skipped by adapter");
        return;
      }
    }

    var evt = $.Event("shiny:updateinput");
    evt.message = message;
    evt.binding = binding;
    $(el).trigger(evt);
    if (evt.isDefaultPrevented()) {
      record(t, id, "skipped", name, "shiny:updateinput was prevented");
      return;
    }

    try {
      await binding.receiveMessage(el, message);
    } catch (e) {
      record(t, id, "failed", name, errorMessage(e));
      return;
    }

    var status = t.applied[id] ? "reapplied" : "applied";
    var detail = "";
    if (hasExpect) {
      var now = currentValue(binding, el);
      if (!same(now, rec.expect)) {
        status = "mismatched";
        detail = "input reports " + JSON.stringify(now === undefined ? null : now);
      }
    }
    t.applied[id] = true;
    record(t, id, status, name, detail);
  }

  // The transaction in flight, for debugging: window.shinysnap.transaction().
  shinysnap.transaction = function () {
    if (txn === null) return null;
    return {
      id: txn.id,
      order: txn.order.slice(),
      results: JSON.parse(JSON.stringify(txn.results)),
      inflight: txn.inflight,
      lastActivity: txn.lastActivity
    };
  };

  function handleRestore(msg) {
    try {
      startRestore(msg);
    } catch (e) {
      if (window.console && console.error) console.error("[shinysnap] restore failed to start", e);
      throw e;
    }
  }

  function startRestore(msg) {
    clearTransaction();
    if (!msg || !msg.txn) return;
    if (msg.debug) shinysnap.debug = true;
    var t = {
      id: msg.txn,
      records: {},
      order: [],
      results: {},
      applied: {},
      startedAt: Date.now(),
      timeoutAt: Date.now() + (typeof msg.timeout === "number" ? msg.timeout : 10000),
      settleMs: typeof msg.settle === "number" ? msg.settle : 300,
      lastActivity: Date.now(),
      chain: Promise.resolve(),
      inflight: 0,
      timer: null
    };
    var inputs = Array.isArray(msg.inputs) ? msg.inputs : [];
    for (var i = 0; i < inputs.length; i++) {
      var rec = inputs[i];
      if (!rec || !rec.id) continue;
      if (!(rec.id in t.records)) t.order.push(rec.id);
      t.records[rec.id] = rec;
    }
    txn = t;
    log("restore", t.id, "start", t.order.length, "input(s)");
    for (var j = 0; j < t.order.length; j++) {
      if (findBound(t.order[j])) enqueueApply(t, t.order[j], "initial");
    }
    scheduleSettleCheck(t);
  }

  function scheduleSettleCheck(t) {
    t.timer = setTimeout(function () {
      t.timer = null;
      checkSettle(t);
    }, 50);
  }

  function checkSettle(t) {
    if (txn !== t) return;
    var now = Date.now();
    if (now >= t.timeoutAt) {
      settle(t, true);
      return;
    }
    var busy = document.documentElement.classList.contains("shiny-busy");
    if (!busy && t.inflight === 0 && now - t.lastActivity >= t.settleMs) {
      settle(t, false);
      return;
    }
    scheduleSettleCheck(t);
  }

  function settle(t, timedOut) {
    var results = [];
    for (var i = 0; i < t.order.length; i++) {
      var id = t.order[i];
      results.push(
        t.results[id] || { id: id, status: "missing", binding: t.records[id].binding || "", detail: "" }
      );
    }
    var payload = {
      txn: t.id,
      elapsed: Date.now() - t.startedAt,
      timedOut: timedOut,
      results: results
    };
    log("restore", t.id, timedOut ? "timed out" : "settled", payload);
    clearTransaction();
    window.Shiny.setInputValue(".shinysnap_result", payload, { priority: "event" });
  }

  function handleCancel(msg) {
    if (txn !== null && (!msg || !msg.txn || msg.txn === txn.id)) {
      log("restore", txn.id, "cancelled");
      clearTransaction();
    }
  }

  function onBound(evt) {
    if (evt.bindingType !== "input") {
      return;
    }
    scheduleInventory();
    var t = txn;
    if (t === null) return;
    touch(t);
    var id = evt.binding && typeof evt.binding.getId === "function" ? evt.binding.getId(evt.target) : null;
    if (!id || !(id in t.records)) return;
    // Defer past the microtask in which Shiny sends the element's initial
    // value, otherwise that default would overwrite the restored value.
    setTimeout(function () {
      if (txn !== t) return;
      enqueueApply(t, id, "bound");
    }, 0);
  }

  // ----------------------------------------------------------------- install

  function install() {
    var $ = window.jQuery;
    $(document).on("shiny:bound", onBound);
    $(document).on("shiny:unbound", function (evt) {
      if (evt.bindingType === "input") scheduleInventory();
    });
    $(document).on("shiny:busy shiny:message shiny:value", function () {
      touch(txn);
    });
    // A (re)connect resets the server's view of the inputs: report again.
    $(document).on("shiny:connected", announce);
    window.Shiny.addCustomMessageHandler("shinysnap:restore", handleRestore);
    window.Shiny.addCustomMessageHandler("shinysnap:cancel", handleCancel);
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
