#!/usr/bin/env python

from argparse import ArgumentParser
from pathlib import Path
import configparser
import sys
import time
# import requests
import os.path


def parse_cmdline():
    '''parse the command line arguments'''
    # Create object for the command line arguments
    parser = ArgumentParser(description="Command line internet radio recorder (for crontab)")
    parser.add_argument("-r", "--radio",    required=True, type=ascii, help="Name of the radio station")
    parser.add_argument("-d", "--duration", required=True, type=int,   help="Duration of the recording in minutes")
    parser.add_argument("-s", "--show",     required=True, type=ascii, help="Name of the Radio show")

    return parser.parse_args()


def get_config():
    '''Read the config file.'''

    conf_file = str(Path.home()) + "/.pyrecorder.conf"

    if not os.path.isfile(conf_file):
        print("Missing config file " + conf_file)
        sys.exit(1)

    config = configparser.ConfigParser()
    config.read(conf_file)

    # Initialise the dictionary to store the config file
    dictionary = {}
    dictionary['global'] = {}

    dictionary['global']['savedir'] = str(config.get('global', 'savedir')).strip('"')

    # parse config file and store it to the dictionary:
    # We want to proces the config sections as long it is not global:
    for section in [x for x in config.sections() if x != "global"]:
        dictionary[section] = {}
        # Handle missing fullname parameter
        try:
            dictionary[section]['fullname'] = config.get(section, "fullname")
        except configparser.NoOptionError:
            # If fullname is not set just take the section name
            dictionary[section]['fullname'] = section

        # handle the file suffix parameter for the saved file. Is optional, defaults to mp3
        try:
            dictionary[section]['suffix'] = config.get(section, 'suffix')
        except configparser.NoOptionError:
            dictionary[section]['suffix'] = "mp3"

        # what to do with a missing url parameter..
        try:
            dictionary[section]['url']      = config.get(section, "url")
        except configparser.NoOptionError:
            print("Section " + section + " needs an url! Stopping cowardly...")
            sys.exit(1)

    # Return dictionary of radio configs to the caller of the function
    return dictionary


def prepare_directories(full_path):
    '''Ensure the directory for saving the recording exists'''
    print("* Preparing directory: " + full_path)

    # defining the path where the recordings are saved:
    os.makedirs(full_path, exist_ok=True)


def get_timestring():
    '''get a date string for the recorded file'''
    from datetime import datetime

    now = datetime.now()  # current date and time
    return now.strftime("%Y_%m_%d-%H_%M")


def show_record_settings(rip_settings):
    '''Just print all the settings for the recorded live stream'''

    print("The recording will start with the following settings:")
    print("* Radio station: " + rip_settings['fullname'])
    print("* Radio show:    " + rip_settings['show'])
    print("* Duration:      " + str(rip_settings['duration']) + " minutes")
    print("* Record file:   " + rip_settings['file_path'])
    print()


def start_recording(filepath, stream_url):
    '''
    This records the actual livestream. It needs to be started
    as a subprocesso so we can stop it after the right time.
    '''

    import requests
    try:
        req = requests.get(stream_url, stream=True)
    except requests.exceptions.ConnectionError:
        print("Not able to connect to url " + stream_url + " !!")
        sys.exit(1)

    print("* Recording from URL: " + stream_url)
    print("* Writing to file: " + filepath)
    with open(filepath, 'wb') as file:
        try:
            for block in req.iter_content(1024):
                file.write(block)
        except KeyboardInterrupt:
            pass


def record_stream(rip_settings):
    ''' start recording the live stream'''
    from multiprocessing import Process

    proc = Process(target=start_recording, args=(rip_settings['file_path'], rip_settings['url']))
    proc.start()
    time.sleep(rip_settings['duration'] * 60)
    proc.terminate()


def main():
    '''Main function'''
    # get settings from config file
    radio_config  = get_config()
    # get parameter from the command line
    cmd_line_args = parse_cmdline()

    # Without strip we get ugly qoutes
    radio    = str(cmd_line_args.radio).strip("'")
    show     = str(cmd_line_args.show).strip("'")
    savedir  = radio_config['global']['savedir']
    full_path = savedir + "/" + radio + "/" + show

    # check if the radio station exists
    if radio not in radio_config.keys():
        print("Radio station " + radio + " is not found in config file!")
        sys.exit(1)

    rip_settings = {}
    rip_settings['radio']     = radio
    rip_settings['show']      = str(cmd_line_args.show).strip("'")
    rip_settings['fullname'] = str(radio_config[radio]['fullname'])
    rip_settings['duration']  = cmd_line_args.duration
    rip_settings['file_path'] = full_path + "/" + show + "_" + get_timestring() + "." + str(radio_config[radio]['suffix'])
    rip_settings['url']       = str(radio_config[radio]['url']).strip("\"")

    show_record_settings(rip_settings)
    prepare_directories(full_path)
    record_stream(rip_settings)


if __name__ == '__main__':
    main()
