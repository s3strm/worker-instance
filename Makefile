SHELL = /bin/bash

include ./secrets.mk
POSTER_HEIGHT = 900
.PRECIOUS: \
  outgoing/%/ffprobe.txt \
  outgoing/%/video.nfo \
  outgoing/%/kodi.strm \
  outgoing/%/omdb.json \
  outgoing/%/poster.jpg \
  outgoing/%/video.mp4

.PHONY: import export outgoing/% upload/%

EXPORTABLE_FILES = $(wildcard ${INCOMING_DIR}/tt*)
UPLOADABLE_FILES = $(wildcard ./outgoing/tt*/*)

# populate `import/` with data from the ftp server
import:
	./bin/ftp_import

# populate `export/` with data from `import/`
export:
	for f in ${EXPORTABLE_FILES}; do              \
		./bin/export_from_incoming $$f || exit 1;  \
	done

upload:
	for f in ${UPLOADABLE_FILES}; do              \
		./bin/upload_from_outgoing $$f || exit 1;  \
	done
	cp -aux ./outgoing/* ./kodi/library/

outgoing/%/video.mp4:
	mkdir -p outgoing/$*
	mv ${INCOMING_DIR}/$*.mp4 $@ \
		|| ffmpeg -y -fflags +genpts -i "${INCOMING_DIR}/$*.avi" -c copy "$@" \
		|| ffmpeg -y -fflags +genpts -i "${INCOMING_DIR}/$*.mkv" -c copy "$@"
	rm -f ${INCOMING_DIR}/$*.avi ${INCOMING_DIR}/$*.mkv

outgoing/%/english.srt:
	mkdir -p outgoing/$*
	[[ -f ${INCOMING_DIR}/$*.srt ]] && mv ${INCOMING_DIR}/$*.srt $@

outgoing/%/ffprobe.txt: outgoing/%/video.mp4
	mkdir -p outgoing/$*
	ffprobe -i "$<" -show_entries stream > "$@" 2> /dev/null

outgoing/%/omdb.json:
	mkdir -p outgoing/$*
	curl "http://www.omdbapi.com/?apikey=${OMDB_API_KEY}&i=$*&plot=full&r=json" \
		2> /dev/null | jq . > $@
	[[ $$(jq -r .Title $@) != 'null' ]] || rm $@
	[[ -f $@ ]]

outgoing/%/video.nfo: outgoing/%/omdb.json outgoing/%/ffprobe.txt
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
	cp ${INCOMING_DIR}/$*.jpg $@ \
		|| wget "${S3STRM_ADDR}/$*/poster.jpg" -O $@ \
		|| wget "http://img.omdbapi.com/?i=$*&apikey=${OMDB_API_KEY}&h=${POSTER_HEIGHT}" -O $@ \
		|| rm -f $@

clean:
	rm -Rf outgoing/tt*
