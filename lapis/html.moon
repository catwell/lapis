
import concat from table

_G = _G
import type, pairs, ipairs, tostring from _G

punct = "[%^$()%.%[%]*+%-?]"
escape_patt = (str) ->
  (str\gsub punct, (p) -> "%"..p)

html_escape_entities = {
  ['&']: '&amp;'
  ['<']: '&lt;'
  ['>']: '&gt;'
  ['"']: '&quot;'
  ["'"]: '&#039;'
}

html_unescape_entities = {}
for key,value in pairs html_escape_entities
  html_unescape_entities[value] = key

html_escape_pattern = "[" .. concat([escape_patt char for char in pairs html_escape_entities]) .. "]"

escape = (text) ->
  (text\gsub html_escape_pattern, html_escape_entities)

unescape = (text) ->
  (text\gsub "(&[^&]-;)", (enc) ->
    decoded = html_unescape_entities[enc]
    decoded if decoded else enc)

strip_tags = (html) ->
  html\gsub "<[^>]+>", ""

void_tags = {
    "area"
    "base"
    "br"
    "col"
    "command"
    "embed"
    "hr"
    "img"
    "input"
    "keygen"
    "link"
    "meta"
    "param"
    "source"
    "track"
    "wbr"
}

for tag in *void_tags
  void_tags[tag] = true

------------------

element_attributes = (buffer, t) ->
  return unless type(t) == "table"

  padded = false
  for k,v in pairs t
    if type(k) == "string" and not k\match "^__"
      if not padded
        buffer\write " "
        padded = true
      buffer\write k, "=", '"', escape(tostring(v)), '"'
  nil

element = (buffer, name, attrs, ...) ->
  with buffer
    \write "<", name
    element_attributes(buffer, attrs)
    if void_tags[name]
      -- check if it has content
      has_content = false
      for thing in *{attrs, ...}
        t = type thing
        switch t
          when "string"
            has_content = true
            break
          when "table"
            if thing[1]
              has_content = true
              break

      unless has_content
        \write "/>"
        return buffer

    \write ">"
    \write_escaped attrs, ...
    \write "</", name, ">"

class Buffer
  builders: {
    html_5: (...) ->
      raw '<!DOCTYPE HTML>'
      raw '<html lang="en">'
      text ...
      raw '</html>'
  }

  new: (@buffer) =>
    @old_env = {}
    @i = #@buffer
    @make_scope!

  with_temp: (fn) =>
    old_i, old_buffer = @i, @buffer
    @i = 0
    @buffer = {}
    fn!
    with @buffer
      @i, @buffer = old_i, old_buffer

  make_scope: =>
    @scope = setmetatable { [Buffer]: true }, {
      __index: (scope, name) ->
        handler = switch name
          when "widget"
            (w) ->
              w._parent = @widget

              -- add helpers from parents
              for helper in *@widget\_get_helper_chain!
                w\include_helper helper

              w\render @
          when "capture"
            (fn) -> table.concat @with_temp -> fn!
          when "element"
            (...) -> element @, ...
          when "text"
            @\write_escaped
          when "raw"
            @\write

        unless handler
          default = @old_env[name]
          return default unless default == nil

        unless handler
          builder = @builders[name]
          unless builder == nil
            handler = (...) -> @call builder, ...

        unless handler
          handler = (...) -> element @, name, ...

        scope[name] = handler
        handler
    }

  call: (fn, ...) =>
    env = getfenv fn
    out = nil
    if env == @scope
      out = {fn ...}
    else
      before = @old_env
      -- env[Buffer] is true with we have a broken function
      -- a function that errored out mid way through a previous render
      @old_env = env[Buffer] and _G or env
      setfenv fn, @scope
      out = {fn ...}
      setfenv fn, env
      @old_env = before

    unpack out

  write_escaped: (thing, next_thing, ...) =>
    switch type thing
      when "string"
        @write escape thing
      when "table"
        for chunk in *thing
          @write_escaped chunk
      else
        @write thing

    if next_thing -- keep the tail call
      @write_escaped next_thing, ...

  write: (thing, next_thing, ...) =>
    switch type thing
      when "string"
        @i += 1
        @buffer[@i] = thing
      when "number"
        @write tostring thing
      when "nil"
        nil -- ignore
      when "table"
        for chunk in *thing
          @write chunk
      when "function"
        @call thing
      else
        error "don't know how to handle: " .. type(thing)

    if next_thing -- keep tail call
      @write next_thing, ...

html_writer = (fn) ->
  (buffer) -> Buffer(buffer)\write fn

render_html = (fn) ->
  buffer = {}
  html_writer(fn) buffer
  concat buffer

helper_key = setmetatable {}, __tostring: -> "::helper_key::"
-- ensures that all methods are called in the buffer's scope
class Widget
  @__inherited: (cls) =>
    cls.__base.__call = (...) => @render ...

  @include: (other_cls) =>
    import mixin_class from require "lapis.util"
    mixin_class @, other_cls

  new: (opts) =>
    -- copy in options
    if opts
      for k,v in pairs opts
        if type(k) == "string"
          @[k] = v

  _set_helper_chain: (chain) => rawset @, helper_key, chain
  _get_helper_chain: => rawget @, helper_key

  _find_helper: (name) =>
    if chain = @_get_helper_chain!
      for h in *chain
        helper_val = h[name]
        if helper_val != nil
          -- call functions in scope of helper
          value = if type(helper_val) == "function"
            (w, ...) -> helper_val h, ...
          else
            helper_val

          return value

  -- insert table onto end of helper_chain
  include_helper: (helper) =>
    if helper_chain = @[helper_key]
      insert helper_chain, helper
    else
      @_set_helper_chain { helper }
    nil

  content_for: (name) =>
    @_buffer\write_escaped @[name]

  content: => -- implement me

  render_to_string: (...) =>
    buffer = {}
    @render buffer, ...
    concat buffer

  render: (buffer, ...) =>
    @_buffer = if buffer.__class == Buffer
      buffer
    else
      Buffer buffer

    old_widget = @_buffer.widget
    @_buffer.widget = @

    meta = getmetatable @
    index = meta.__index
    index_is_fn = type(index) == "function"

    seen_helpers = {}
    scope = setmetatable {}, {
      __tostring: meta.__tostring
      __index: (scope, key) ->
        value = if index_is_fn
          index scope, key
        else
          index[key]

        -- run method in buffer scope
        if type(value) == "function"
          wrapped = (...) -> @_buffer\call value, ...
          scope[key] = wrapped
          return wrapped

        -- look for helper
        if value == nil and not seen_helpers[key]
          helper_value = @_find_helper key
          seen_helpers[key] = true
          if helper_value != nil
            scope[key] = helper_value
            return helper_value

        value
    }

    setmetatable @, __index: scope
    @content ...
    setmetatable @, meta

    @_buffer.widget = old_widget
    nil

{ :Widget, :html_writer, :render_html, :escape, :unescape }

