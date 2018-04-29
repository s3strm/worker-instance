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

.PHONY: outgoing/% upload/%

define BACKBLAZE_AUTHORIZE_ACCOUNT
	backblaze-b2 authorize-account \
		${BACKBLAZE_ACCOUNT_ID} \
		${BACKBLAZE_APPLICATION_KEY}
endef

outgoing/%/video.mp4:
	mkdir -p outgoing/$*
	mv ./incoming/$*.mp4 $@ \
		|| ffmpeg -y -fflags +genpts -i "incoming/$*.avi" -c copy "$@" \
		|| ffmpeg -y -fflags +genpts -i "incoming/$*.mkv" -c copy "$@" \
		|| aws s3 cp s3://${S3_MOVIE_BUCKET}/$*/video.mp4 $@

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

clean:
	rm -Rf outgoing/tt*
