SHELL = /bin/bash
include ./secrets.mk
include ./bb_token.mk

BACKBLAZE_WGET = wget --header='Authorization: ${BACKBLAZE_ACCOUNT_AUTHORIZATION_TOKEN}'
BACKBLAZE_PATH = ${BACKBLAZE_API_URL}/file/${BACKBLAZE_MOVIE_BUCKET}

POSTER_HEIGHT = 900

EXPORTABLE_FILES = $(wildcard ${INCOMING_DIR}/tt*)
UPLOADABLE_FILES = $(wildcard ./outgoing/tt*/*)

# populate `import/` with data from the ftp server
.PHONY: import
import:
	./bin/ftp_import

.PHONY: download_batch
download_batch:
	./bin/download_batch
	$(MAKE) update_library

.PHONY: update_library
update_library:
	-/usr/bin/kodi-send --action "UpdateLibrary(video)"

# populate `export/` with data from `import/`
.PHONY: export
export:
ifneq (,${EXPORTABLE_FILES})
	for f in ${EXPORTABLE_FILES}; do              \
		./bin/export_from_incoming $$f || exit 1;  \
	done
	$(MAKE) update_library
endif

.PHONY: upload
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

outgoing/%/video.en.srt:
	mkdir -p outgoing/$*
	-${BACKBLAZE_WGET} "${BACKBLAZE_PATH}/$*/video.en.srt" -O $@
	[[ -s $@ ]] || rm -f $@   # delete downloaded file has a zero-length
	[[ -f ${INCOMING_DIR}/$*.srt ]] && mv ${INCOMING_DIR}/$*.srt $@

.DELETE_ON_ERROR: outgoing/%/ffprobe.txt
.PRECIOUS: outgoing/%/ffprobe.txt
outgoing/%/ffprobe.txt: outgoing/%/video.mp4
	mkdir -p outgoing/$*
	ffprobe -i "$<" -show_entries stream > "$@" 2> /dev/null
	[[ -s $@ ]]

.DELETE_ON_ERROR: outgoing/%/omdb.json
.PRECIOUS: outgoing/%/omdb.json
outgoing/%/omdb.json:
	mkdir -p outgoing/$*
	curl "http://www.omdbapi.com/?apikey=${OMDB_API_KEY}&i=$*&plot=full&r=json" \
		2> /dev/null | jq . > $@
	[[ $$(jq -r .Title $@) != 'null' ]] || rm $@
	[[ -s $@ ]]

.DELETE_ON_ERROR: outgoing/%/video.nfo
.PRECIOUS: outgoing/%/video.nfo
outgoing/%/video.nfo: outgoing/%/omdb.json outgoing/%/ffprobe.txt
	mkdir -p outgoing/$*
	./bin/kodi_nfo_generator $* > $@

.PRECIOUS: outgoing/%/kodi.strm
outgoing/%/kodi.strm: outgoing/%/ffprobe.txt outgoing/%/omdb.json
	mkdir -p outgoing/$*
	echo -n '#EXTINF:' > $@
	awk -F= '/^duration=/ { print int($$2) }' outgoing/$*/ffprobe.txt | head -n1 | tr -d '\n' >> $@
	echo -n ',' >> $@
	jq -r .Title outgoing/$*/omdb.json >> $@
	echo "${S3STRM_ADDR}/$*/video.mp4" >> $@

.DELETE_ON_ERROR: outgoing/%/poster.jpg
.PRECIOUS: outgoing/%/poster.jpg
outgoing/%/poster.jpg:
	mkdir -p outgoing/$*
	-mv ${INCOMING_DIR}/$*.jpg $@ \
		|| ${BACKBLAZE_WGET} "${BACKBLAZE_PATH}/$*/poster.jpg" -O $@ \
		|| wget "http://img.omdbapi.com/?i=$*&apikey=${OMDB_API_KEY}&h=${POSTER_HEIGHT}" -O $@ \
	[[ -s $@ ]]
