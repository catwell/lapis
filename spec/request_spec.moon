
lapis = require "lapis"

import mock_request, mock_action, assert_request from require "lapis.spec.request"

class App extends lapis.Application
  "/hello": =>

describe "application", ->
  it "should mock a request", ->
    assert.same 200, (mock_request App, "/hello")
    assert.same 500, (mock_request App, "/world")

class SessionApp extends lapis.Application
  layout: false

  "/set_session/:value": =>
    @session.hello = @params.value

  "/get_session": =>
    @session.hello

-- tests a series of requests
describe "session app", ->
  it "should set and read session", ->
    _, _, h = assert_request SessionApp, "/set_session/greetings"
    status, res = assert_request SessionApp, "/get_session", prev: h
    assert.same "greetings", res

describe "mock action", ->
  assert.same "hello", mock_action lapis.Application, "/hello", {}, ->
    "hello"

describe "cookies", ->
  class CookieApp extends lapis.Application
    layout: false
    "/": => @cookies.world = 34

    "/many": =>
      @cookies.world = 454545
      @cookies.cow = "one cool ;cookie"

  class CookieApp2 extends lapis.Application
    layout: false
    cookie_attributes: { "Domain=.leafo.net;" }
    "/": => @cookies.world = 34

  it "should write a cookie", ->
    _, _, h = mock_request CookieApp, "/"
    assert.same "world=34; Path=/; HttpOnly", h["Set-cookie"]

  it "should write multiple cookies", ->
    _, _, h = mock_request CookieApp, "/many"

    assert.same {
      'cow=one%20cool%20%3bcookie; Path=/; HttpOnly'
      'world=454545; Path=/; HttpOnly'
    }, h["Set-cookie"]

  it "should write a cookie with cookie attributes", ->
    _, _, h = mock_request CookieApp2, "/"
    assert.same "world=34; Path=/; HttpOnly; Domain=.leafo.net;", h["Set-cookie"]


describe "before filter", ->
  it "should run before filter", ->
    local val

    class BasicBeforeFilter extends lapis.Application
      @before_filter =>
        @hello = "world"

      "/": =>
        val = @hello

    assert_request BasicBeforeFilter, "/"
    assert.same "world", val

  it "should run before filter with inheritance", ->
    class BasicBeforeFilter extends lapis.Application
      @before_filter => @hello = "world"

    val = mock_action BasicBeforeFilter, =>
      @hello

    assert.same "world", val

  it "should run before filter scoped to app with @include", ->
    local base_val, parent_val

    class BaseApp extends lapis.Application
      @before_filter => @hello = "world"
      "/base_app": => base_val = @hello or "nope"

    class ParentApp extends lapis.Application
      @include BaseApp
      "/child_app": => parent_val = @hello or "nope"

    assert_request ParentApp, "/base_app"
    assert_request ParentApp, "/child_app"

    assert.same "world", base_val
    assert.same "nope", parent_val

  it "should cancel action if before filter writes", ->
    action_run = 0

    class SomeApp extends lapis.Application
      layout: false

      @before_filter =>
        if @params.value == "stop"
          @write "stopped!"

      "/hello/:value": => action_run += 1

    assert_request SomeApp, "/hello/howdy"
    assert.same action_run, 1

    _, res = assert_request SomeApp, "/hello/stop"
    assert.same action_run, 1
    assert.same "stopped!", res


