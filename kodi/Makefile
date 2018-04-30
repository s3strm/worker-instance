SHELL = /bin/bash

include ../secrets.mk

.PHONY: library
.PRECIOUS: bucket.cache

library: bucket.cache
	for p in $$(cat $<); do \
	  f=$$(basename $$p); \
	  if [[ $$f =~ ^kodi ]]; then \
	    echo "fetching $$p"; \
		mkdir -p ./library/$$(dirname $$p) 2> /dev/null; \
	    [[ ! -f ./library/$$p ]] \
		  && wget ${S3STRM_ADDR}/$$p -O ./library/$$p; \
	  fi \
	done

bucket.cache:
	$(info Populating file cache...)
	@../bin/list_movie_bucket_files | sort | uniq > $@

clean:
	rm ./bucket_file.cache
