#!/usr/bin/env python3

"""
This is some exemplaric code how to aquire ADC data with the TeensyLogger
and python on the USB host computer. It was tested with Linux, Python3 and
PySerial (https://pythonhosted.org/pyserial/).


Copyright (c) 2021 Anabrid GmbH, MIT Licensed, see LICENSE file.
"""

import serial, re, time, numpy as np, sys

log = lambda *a,**b: print(*a,**b,file=sys.stderr)

s = serial.Serial(port="/dev/ttyACM0", baudrate=9600, timeout=1)
s.flushInput()

def write(cmd):
    s.write(cmd.encode("ascii"))    

def query2(cmd):
    write(cmd)
    #s.flush()
    time.sleep(1) # give it some time to answer
    buf = b""
    read_attempts = 3
    while True:
        readin = s.readline()
        buf += readin
        #print(f"{read_attempts=}, {readin=}")
        if len(readin) == 0:
            # end of buffer or nothing read in
            read_attempts -= 1
            if read_attempts < 0:
                break
    return buf.decode("ascii", "ignore")

def query(cmd):
    write(cmd)
    time.sleep(1) # on second sleep is absolutely required
    # Reading with Backtracking
    max_tries,max_wait_sec = 8, 2.0
    for i in range(max_tries):
        bytes_to_read = s.inWaiting()
        if bytes_to_read:
            return s.read(bytes_to_read).decode("ascii", "ignore")
        else:
            wait_time_sec = max_wait_sec * 0.1**(max_tries-i-1)
            print(f"{wait_time_sec=}")
            time.sleep(wait_time_sec)
    return ""

helpmsg = query("?").split("\n")
if len(helpmsg) < 10:
    raise ValueError(f"Could not properly connect, asked for ? got {helpmsg=}")
log(f"Teensy: Connected via {s.port} to {helpmsg[0]}")

log("Teensy: ", query("channels=4").strip())
log("Teensy: ", query("interval=10").strip()) # microseconds

# Usage is as following:
#  arm()
#  do some work which fires the trigger
#  checkread() # will raise in case of non-expected trigger output
#  data = dump() # actual data

def arm():
    log("Teensy: ", query("arm").strip())
    
def checkread():
    # we now expect some output such as...
    logline = s.readline().decode("ascii")
    magicline = "Data collection stopped"
    if not magicline in logline:
        raise ValueError(f"Expected {magicline} but got {logline}")
    log("Teensy: ", logline.strip())
    # A sentence like 'Sampling automatically stopped after 16384 samples'
    log("Teensy: ", s.readline().decode("ascii").strip())
    
# Works until here!!
    
def dump():
    data = query("dump") 
    # does not work, data is way to short.
    # check for instance with data.split()
    return data

def another_read():
    s.timeout = 0 # timeout=0 is a shitty idea and breaks everything
    data = b""
    while True:
        bytes_to_read = s.inWaiting()
        if bytes_to_read:
            data += s.read(bytes_to_read)
            print(f"Read {bytes_to_read} bytes...")
        else:
            break
    return data 
