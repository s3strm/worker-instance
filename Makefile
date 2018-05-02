SHELL = /bin/bash

include ./secrets.mk
POSTER_HEIGHT = 900
.PRECIOUS: \
  outgoing/%/ffprobe.txt \
  outgoing/%/kodi.nfo \
  outgoing/%/kodi.strm \
  outgoing/%/omdb.json \
  outgoing/%/poster.jpg \
  outgoing/%/video.mp4

.PHONY: import export outgoing/% upload/%

define BACKBLAZE_AUTHORIZE_ACCOUNT
	backblaze-b2 authorize-account \
		${BACKBLAZE_ACCOUNT_ID} \
		${BACKBLAZE_APPLICATION_KEY}
endef

import:
	./bin/ftp_import

export:
	for imdb_id in $$(find ./incoming/ -type f | xargs -i basename {} | cut -d. -f1 | sort | uniq); do \
		make upload/$${imdb_id}; \
		if [[ -f ./upload/$${imdb_id}.mp4 ]]; then \
			rm -f ./incoming/$${imdb_id}.mp4 ./incoming/$${imdb_id}.mkv ./incoming/$${imdb_id}.avi; \
		fi \
	done

outgoing/%/video.mp4:
	mkdir -p outgoing/$*
	mv ./incoming/$*.mp4 $@ \
		|| ffmpeg -y -fflags +genpts -i "incoming/$*.avi" -c copy "$@" \
		|| ffmpeg -y -fflags +genpts -i "incoming/$*.mkv" -c copy "$@" \
		|| aws s3 cp s3://${S3_MOVIE_BUCKET}/$*/video.mp4 $@
outgoing/%/english.srt:
	mkdir -p outgoing/$*
	[[ -f ./incoming/$*.srt ]] && mv ./incoming/$*.srt $@

outgoing/%/ffprobe.txt: outgoing/%/video.mp4
	mkdir -p outgoing/$*
	ffprobe -i "$<" -show_entries stream > "$@" 2> /dev/null

outgoing/%/omdb.json:
	mkdir -p outgoing/$*
	curl "http://www.omdbapi.com/?apikey=${OMDB_API_KEY}&i=$*&plot=full&r=json" \
		2> /dev/null | jq . > $@
	[[ $$(jq -r .Title $@) != 'null' ]] || rm $@
	[[ -f $@ ]]

outgoing/%/kodi.nfo: outgoing/%/omdb.json outgoing/%/ffprobe.txt
	mkdir -p outgoing/$*
	./bin/kodi_nfo_generator $* > $@

outgoing/%/kodi.strm: outgoing/%/ffprobe.txt outgoing/%/omdb.json
	mkdir -p outgoing/$*
	echo -n '#EXTINF:' > $@
	awk -F= '/^duration=/ { print int($$2) }' outgoing/$*/ffprobe.txt | head -n1 | tr -d '\n' >> $@
	echo -n ',' >> $@
	jq -r .Title outgoing/$*/omdb.json >> $@
	echo "${S3STRM_ADDR}/$*/video.mp4" >> $@

outgoing/%/poster.jpg:
	mkdir -p outgoing/$*
	cp incoming/$*.jpg $@ \
		|| aws s3 cp s3://${S3_MOVIE_BUCKET}/$*/poster-custom.jpg $@ \
		|| aws s3 cp s3://${S3_MOVIE_BUCKET}/$*/poster.jpg $@ \
		|| wget "http://img.omdbapi.com/?i=$*&apikey=${OMDB_API_KEY}&h=${POSTER_HEIGHT}" -O $@ \
		|| rm -f $@

upload/%: outgoing/%/video.mp4 outgoing/%/poster.jpg outgoing/%/kodi.strm outgoing/%/kodi.nfo outgoing/%/omdb.json outgoing/%/ffprobe.txt
	${BACKBLAZE_AUTHORIZE_ACCOUNT} && \
		backblaze-b2 upload-file --noProgress \
			${BACKBLAZE_MOVIE_BUCKET} ./outgoing/$*/video.mp4 $*/video.mp4
	${BACKBLAZE_AUTHORIZE_ACCOUNT} && \
		backblaze-b2 upload-file --noProgress \
			${BACKBLAZE_MOVIE_BUCKET} ./outgoing/$*/poster.jpg $*/poster.jpg
	${BACKBLAZE_AUTHORIZE_ACCOUNT} && \
		backblaze-b2 upload-file --noProgress --contentType application/xml \
			 ${BACKBLAZE_MOVIE_BUCKET} ./outgoing/$*/kodi.nfo $*/kodi.nfo
	${BACKBLAZE_AUTHORIZE_ACCOUNT} && \
		backblaze-b2 upload-file --noProgress --contentType application/text \
			${BACKBLAZE_MOVIE_BUCKET} ./outgoing/$*/kodi.strm $*/kodi.strm
	${BACKBLAZE_AUTHORIZE_ACCOUNT} && \
		backblaze-b2 upload-file --noProgress \
			${BACKBLAZE_MOVIE_BUCKET} ./outgoing/$*/omdb.json $*/omdb.json
	${BACKBLAZE_AUTHORIZE_ACCOUNT} && \
		backblaze-b2 upload-file --noProgress \
			${BACKBLAZE_MOVIE_BUCKET} ./outgoing/$*/ffprobe.txt $*/ffprobe.txt
	[[ -f ./outgoing/$*/english.srt ]] \
		&& ${BACKBLAZE_AUTHORIZE_ACCOUNT} && \
			backblaze-b2 upload-file --noProgress --contentType text/srt \
				${BACKBLAZE_MOVIE_BUCKET} ./outgoing/$*/english.srt $*/english.srt
	mkdir -p kodi/library/$*
	cp ./outgoing/$*/kodi.nfo kodi/library/$*
	cp ./outgoing/$*/kodi.strm kodi/library/$*

clean:
	rm -Rf outgoing/tt*
