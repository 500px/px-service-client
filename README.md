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

class MyClient < Px::Service::Client::Base
  include Px::Service::Client::Caching
  include Px::Service::Client::CircuitBreaker
end

```

Features
--------

This gem includes several common features used in 500px service client libraries.

The features are:

#### Px::Service::Client::Base
This class provides a basic `make_request(method, url, ...)` method that produces an asynchronous request. The method immediately returns a `Future`. It works together with `Multiplexer`(discussed below) and uses [Typhoeus](https://github.com/typhoeus/typhoeus)  as the underlying HTTP client to support asynchronicity. 

**Clients should subclass this class and include other features/mixins, if needed.**  

# Optional
config do |config|
  config.statsd_client = Statsd.new(host, port)
end


See the following section for an example of how to use `make_request` and `Multiplexer`.

#### Px::Service::Client::Multiplexer
This class works together with `Px::Service::Client::Base` sub-classes to support request parallel execution.

Example:

```Ruby
multi = Px::Service::Client::Multiplexer.new

multi.context do
	method = :get
	url = 'http://www.example.com'
	req = make_request(method, url) # returns a Future
	multi.do(req) # queues the request/future into hydra
end

multi.run # a blocking call, like hydra.run

```
`multi.context` encapsulates the block into a [`Fiber`](http://ruby-doc.org/core-2.2.0/Fiber.html) object and immediately runs (or `resume`, in Fiber's term) that fiber until the block explicitly gives up control. The method returns `multi` itself.

`multi.do(request_or_future,retries)` queues the request into `hydra`. It always returns a `Future`. A  [`Typhoeus::Request`](https://github.com/typhoeus/typhoeus) will be converted into a `Future ` in this call. 

Finally, `multi.run` starts `hydra` to execute the requests in parallel. The request is made as soon as the multiplexer is started. You get the results of the request by evaluating the value of the `Future`.

#### Px::Service::Client::Caching

Provides client-side response caching of service requests.  

```ruby
include Px::Service::Client::Caching

# Optional
config do |config|
  config.cache_strategy = :none
  config.cache_expiry = 30.seconds
  config.max_page = nil
  config.cache_options = {}
  config.cache_options[:policy_group] = 'general'
  config.cache_client =  Dalli::Client.new(...)
  config.cache_logger = Logger.new(STDOUT) # or Rails.logger, for example
end

# An example of a cached request
result = cache_request(url, :last_resort, refresh_probability: 1) do
	req = make_request(method, url)
	response = @multi.do(req)
	
	# cache_request() expects a future that returns the result to be cached
	Px::Service::Client::Future.new do  
		JSON.parse(response.body)
	end
end
```

`cache_request` expects a block that returns a `Future` object. The return value (usually the response body) of that future will be cached.  `cache_request` always returns a future. By evaluating the future, i.e., via the `Future.value!` call, you get the result (whether cached or not). 


**Note**: DO NOT cache the `Typhoeus::Response` directly (See the below code snippet), because the response object cannot be serializable to be stored in memcached. That's the reason why we see warning message: `You are trying to cache a Ruby object which cannot be serialized to memcached.`

```
# An incorrect example of using cache_request()
cache_request(url, :last_resort) do
	req = make_request(method, url)
	response = @multi.do(req)   # DO NOT do this 
end

``` 
Responses are cached in either a *last-resort* or *first-resort* manner.

*last-resort* means that the cached value is only used when the service client request fails (with a
`ServiceError`). If the service client request succeeds, there is a chance that the cache value may get refreshed. The `refresh_probability` is provided to let the cached value
be refreshed probabilistically (rather than on every request).

If the service client request fails and there is a `ServiceError`, `cache_logger` will record the exception message, and attempt to read the existing cache value.

*first-resort* means that the cached value is always used, if present.  If the cached value is present but expired, the it sends the service client request and, if the request succeeds, it refreshes the cached value expiry. If the request fails, it uses the expired cached value, but the value remain expired. A retry may be needed.



#### Px::Service::Client::CircuitBreaker
This mixin overrides `Px::Service::Client::Base#make_request` method and implements the circuit breaker pattern.

```ruby
include Px::Service::Client::CircuitBreaker

# Optional
circuit_handler do |handler|
 handler.logger = Logger.new(STDOUT)
 handler.failure_threshold = 5
 handler.failure_timeout = 5
 handler.invocation_timeout = 10
 handler.excluded_exceptions += [NotConsideredFailureException]
end

# An example of a make a request with circuit breaker
req = make_request(method, url) # overrides Px::Service::Client::Base
```

Adds a circuit breaker to the client.  `make_request` always returns `Future`

The circuit will open on any exception from the wrapped method, or if the request runs for longer than the `invocation_timeout`.

If the circuit is open, any future request will be get an error message wrapped in `Px::Service::ServiceError`.

By default, `Px::Service::ServiceRequestError` is excluded by the handler. That is, when the request fails with a `ServiceRequestError` exceptions, the same `ServiceRequestError` will be raised. But it does NOT increase the failure count or trip the breaker, as these exceptions indicate an error on the caller's part (e.g. an HTTP 4xx error).

Every instance of the class that includes the `CircuitBreaker` concern will share the same circuit state.  You should therefore include `Px::Service::Client::CircuitBreaker` in the most-derived class that subclasses
`Px::Service::Client::Base`.

This module is based on (and uses) the [Circuit Breaker](https://github.com/wsargent/circuit_breaker) gem by Will Sargent.

#### Px::Service::Client::HmacSigning
Similar to `Px::Service::Client::CircuitBreaker`, this mixin overrides `Px::Service::Client::Base#make_request` method and appends a HMAC signature in the request header.

To use this mixin:

```ruby
class MyClient < Px::Service::Client::Base
	include Px::Service::Client::HmacSigning

	#optional
	config do |config|
		config.hmac_secret = 'mykey'
		config.hmac_keyspan = 300
	end
end
```

Note: `key` and `keyspan` are class variables and shared among instances of the same class.

The signature is produced from the secret key, a nonce, HTTP method, url, query, body. The nonce is generated from the timestamp.

To retrieve and verify the signature:

```ruby
# Make a request with signed headers
resp = make_request(method, url, query, headers, body)

signature = resp.request.options[:headers]["X-Service-Auth"]
timestamp = resp.request.options[:headers]["Timestamp"]

# Call the class method to regenerate the signature
expected_signature = MyClient.generate_signature(method, url, query, body, timestamp)

# assert signature == expected_signature
```

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
