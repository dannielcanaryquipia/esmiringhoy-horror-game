Esmiringhoy trailer recorder
============================
A ~61 s scripted trailer recorded with Godot's Movie Maker (fixed 30 fps, so the
video is smooth even if your PC can't render that fast in real time).

Easiest: double-click  record_trailer.bat  in the project folder.
It imports the project, then opens a window and records to:
    trailer_out\esmiringhoy_trailer.ogv     (Theora video + Vorbis audio)
Don't touch the window while it records; it closes itself when done.

Convert to MP4 for YouTube / itch.io (needs ffmpeg):
    ffmpeg -i trailer_out\esmiringhoy_trailer.ogv -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k esmiringhoy_trailer.mp4

Debug tip: set TRAILER_START=36 before running to start mid-timeline.
This folder is not needed by the game: exclude "trailer/*" and "trailer_out/*" in export presets.
