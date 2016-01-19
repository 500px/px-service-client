px-service-client
=================

[![Build Status](https://semaphoreapp.com/api/v1/projects/3e3b69a9-7606-49d9-a9e1-acea22b026c4/277528/badge.png)](https://semaphoreapp.com/500px/ruby-service-client)

A set of modules to add common functionality to a Ruby service client

Usage
-----

```
gem install px-service-client
```

Or, with bundler

```ruby
gem 'px-service-client'
```

Then use it:

```ruby
require 'px-service-client'

class MyClient
  include Px::Service::Client::Caching
  include Px::Service::Client::CircuitBreaker
end

```

Features
--------

This gem includes several common features used in 500px service client libraries.

The features are:

#### Px::Service::Client::Caching

```ruby
include Px::Service::Client::Caching

# Optional
caching do |config|
  config.cache_strategy = :none
  config.cache_expiry = 30.seconds
  config.max_page = nil
  config.cache_options = {}
  config.cache_options[:policy_group] = 'general'
  config.cache_client =  Dalli::Client.new(...)
  config.cache_logger = Logger.new(STDOUT) # or Rails.logger, for example
end
```

Provides client-side response caching of service requests.  Responses are cached in memcached (using the provided cache client) in either a *last-resort* or *first-resort* manner.

*last-resort* means that the cached value is only used when the service client request fails (with a
`ServiceError`).  When using last-resort caching, a `refresh_probability` can be provided that causes the cached value
to be refreshed probabilistically (rather than on every request).

*first-resort* means that the cached value is always used, if present.  Requests to the service are only made
when the cached value is close to expiry.

An example of a cached request:

```ruby
req = subject.make_request(method, url)
result = subject.cache_request(url) do
  resp = nil
  multi.context do
    resp = multi.do(req)
  end.run

  resp
end
```

`cache_request` expects a block that returns a `RetriableResponseFuture`. It then returns a `Typhoeus::Response`.

#### Px::Service::Client::CircuitBreaker

```ruby
# Optional
circuit_handler do |handler|
 handler.logger = Logger.new(STDOUT)
 handler.failure_threshold = 5
 handler.failure_timeout = 5
 handler.invocation_timeout = 10
 handler.excluded_exceptions += [NotConsideredFailureException]
end
```

Adds a circuit breaker to the client.  The circuit will open on any exception from the wrapped method, or if the request runs for longer than the `invocation_timeout`.

Note that `Px::Service::ServiceRequestError` exceptions do NOT trip the breaker, as these exceptions indicate an error on the caller's part (e.g. an HTTP 4xx error).

Every instance of the class that includes the `CircuitBreaker` concern will share the same circuit state.  You should therefore include `Px::Service::Client::CircuitBreaker` in the most-derived class that subclasses
`Px::Service::Client::Base`

This module is based on (and uses) the [Circuit Breaker](https://github.com/wsargent/circuit_breaker) gem by Will Sargent.

#### Px::Service::Client::ListResponse

```ruby
  def get_something(page, page_size)
    response = JSON.parse(http_get("http://some/url?p=#{page}&l=#{page_size}"))
    return Px::Service::Client::ListResponse(page_size, response, "items")
  end

```

Wraps a deserialized response.  A `ListResponse` implements the Ruby `Enumerable` module, as well
as the methods required to work with [WillPaginate](https://github.com/mislav/will_paginate).

It assumes that the response resembles this form:
```json
{
  "current_page": 1,
  "total_items": 100,
  "total_pages": 10,
  "items": [
    { /* item 1 */ },
    { /* item 2 */ },
    ...
  ]
}
```

The name of the `"items"` key is given in the third argument.

License
-------

The MIT License (MIT)

Copyright (c) 2014 500px, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
