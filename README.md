# TeensyLogger
This repository holds all code and schematics for a simple eight channel
data logger based on a Teensy 4.1. This was developed with analog computing
in mind but can be used for basically anything requiring not more than eight
channels and ideally having a TTL trigger signal available.

## Hardware
The TeensyLogger is a very simple eight channel data recorder based on a
Teensy 4.1 as shown below:

![OverallImg](prototype_2.jpg)

The overall setup is pretty simple and consists of a Teensy 4.1 (which was
at hand when I built it - other Teensy variants might be more suitable as
some of these feature an external reference voltage input which the 4.1 is
missing), eight simple level shifters which map an input signal ranging
between +15 V and -15 V to the permissible input range of 0 .. 3V3 of the 
Teensy itself. These level shifters require a common reference voltage 
which is derived by a voltage divider followed by a buffer amplifier. The
last part of the schematic shown below is the protection circuit for the 
trigger input. The TeensyLogger will start gathering data on a falling edge
of the trigger input and stop data collection at the next rising edge.

![Schematic](TeensyLogger.jpg)

## Firmware
The firmware for the TeensyLogger is written in C++ using the Teensyduino
IDE and can be found here: [Firmware](TeensyLogger)

The firmware can be used either manually by connecting a terminal application
to the USB port of the TeensyLogger or by using the Perl module TeensyLogger.pm
described below.

The following commands are implemented in the firmware:

- ?: Print help.
- arm: Arm the TeensyLogger for data sampling which will commence either when
       an external trigger signal is fed to the TeensyLogger or if the start
       command (see below) is issued.

