service-client
==============

A set of modules to add common functionality to a Ruby service client

Usage
-----

```
gem install service-client
```

Or, with bundler

```ruby
gem 'service-client'
```

Then use it:

```ruby
require 'service-client'

class MyClient
  include Service::Client::Caching
  include Service::Client::CircuitBreaker
end

```

Features
--------

This gem includes several common features used in 500px service client libraries.

The features are:

**Service::Client::Caching**

```ruby
include Service::Client::Caching

self.cache_client =  Dalli::Client.new(...)
self.cache_logger = Logger.new(STDOUT) # or Rails.logger, for example

```

Provides client-side response caching.  Responses are cached in memcached (using the provided cache client)
in either a *last-resort* or *first-resort* manner.

*last-resort* means that the cached value is only used when the service client request fails (with a
`ServiceError`).  When using last-resort caching, a `refresh_probability` can be provided that causes the cached value
to be refreshed probabilistically (rather than on every request).

*first-resort* means that the cached value is always used, if present.  Requests to the service are only made
when the cached value is close to expiry.

**Service::Client::CircuitBreaker**

Provides client-side response caching.  Responses are cached in memcached (using the provided cache client)
in either a *last-resort* or *first-resort* manner.

*last-resort* means that the cached value is only used when the service client request fails (with a
`ServiceError`).  When using last-resort caching, a `refresh_probability` can be provided that causes the cached value
to be refreshed probabilistically (rather than on every request).

*first-resort* means that the cached value is always used, if present.  Requests to the service are only made
when the cached value is close to expiry.

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
