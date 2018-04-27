SHELL = /bin/bash

include ./secrets.mk
POSTER_HEIGHT = 900
.PRECIOUS: outgoing/%/video.mp4 outgoing/%/omdb.json outgoing/%/kodi.nfo outgoing/%/poster.jpg outgoing/%/kodi.strm
.PHONY: outgoing/% upload/%

outgoing/%: outgoing/%/kodi.nfo outgoing/%/kodi.strm outgoing/%/poster.jpg
	ls $@

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

outgoing/%/kodi.strm:
	echo "${S3STRM_ADDR}/$*/video.mp4" > $@

outgoing/%/poster.jpg:
	mkdir -p outgoing/$*
	cp incoming/$*.jpg $@ \
		|| aws s3 cp s3://${S3_MOVIE_BUCKET}/$*/poster-custom.jpg $@ \
		|| aws s3 cp s3://${S3_MOVIE_BUCKET}/$*/poster.jpg $@ \
		|| wget "http://img.omdbapi.com/?i=$*&apikey=${OMDB_API_KEY}&h=${POSTER_HEIGHT}" -O $@ \
		|| rm -f $@

upload/%: outgoing/%
	./bin/backblaze_upload ./outgoing/$*/poster.jpg $*/poster.jpg
	./bin/backblaze_upload ./outgoing/$*/kodi.nfo $*/kodi.nfo
	./bin/backblaze_upload ./outgoing/$*/kodi.strm $*/kodi.strm
	./bin/backblaze_upload ./outgoing/$*/omdb.json $*/omdb.json
	./bin/backblaze_upload ./outgoing/$*/video.mp4 $*/video.mp4

clean:
	rm -Rf outgoing/tt*
