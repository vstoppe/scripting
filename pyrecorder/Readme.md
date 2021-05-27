# Abstract

Pyrecorder is a little script for recording intert radio shows. It is intended to be used in conjunction with crond or a similar scheduling service. I wrote it
to get again more familiar with python.


# Requirements

The following non standard Python modules are required:

* requests

You can also install the requirements file:

`pip install -r requirements.txt`


# Usage

`pyrecorder -r RADIO -s SHOW -d DURATION`

* -r/--radio: Takes the name of the radio to record from
* -r/--show:  This gives the recording a name.
* -d/--duration: Duration of the recording in minutes.


# Configuration

The configuration is done in the file ~/.pyrecorder.conf. This is an example:

	[global]
	savedir="./recordings"

	[dlf]
	fullname=Deutschlandfunk
	url="https://st01.sslstream.dlf.de/dlf/01/high/aac/stream.aac"
	suffix=aac

	[radio_hannover]
	#fullname="Radio Hannover"
	url="https://radio-hannover.divicon-stream.com/live/mp3-192/Homepage/play.pls"

In the global section wie define by savedir uder which location the recording should be saved.

For each radio station we need a section: 

* The shortname for the radio station (-r/--radio) is in the brackets. 
* The fullname is optional. It is just for displaying what will be recorded. 
* suffix ist also optional. If the stream is not mp3 (default), you can set an optional suffix like "aac" or "ogg".
* url is mandatory: This is the URL for the live stream.
