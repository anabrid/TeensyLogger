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
- benchmark: This will perform 1000 AD conversions and return the time 
       required for a single conversion of a given number of input channels.
- channels=x: This command is used to set the number of channels to be sampled.
       Valid values of x are in the interval 1 to 8.
- dump: Dump all data gathered during a sampling period to the USB port. The
       values are printed as floating point numbers in the interval -1..1,
       with individual channels delimited by whitespace.
- interval=x: Set the sampling interval to x microseconds (it should not be 
       set to a value lower than that returned by executing the benchmark
       command to avoid data loss during sampling).
- ms=x: Set the maximum number of sampling points to x. When x is reached 
       during a data gathering operation, sampling is automatically stopped.
- reset: Reset the TeensyLogger to its default settings (one channel, no
       oversampling, 1000 microseconds sampling interval).
- sample: Perform a single sampling operation on all configured channels.
- oversampling=x: If values must be smoothed, this can be done by 
       oversampling i.e. reading multiple times from each channel and then
       computing the arithmetic mean over these conversion results. The value
       x is interpreted as exponent of 2 ** x i.e. x=0 results in no 
       oversampling and is the default setting. To perform four consecutive
       reads on each channel during each sampling operating x=2 should be
       set. Please note that oversampling slows the sampling process down 
       quite considerably and also leads to a larger phase error between 
       the individual channels, so it should be used with caution if at all.
- start: Start data gathering. This will end either when the stop command
       is issued or when the maximum number of samples is reached.
- status: Print the current system status.
- stop: Stop the current data gathering operation (or disarm the TeensyLogger
       if it has been armed but not yet triggered).


- 
