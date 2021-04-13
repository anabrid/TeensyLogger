#
#  This tiny module TeensyLogger provides basic connectivity to the Teensy 4.1
# based eight channel data logger.
#
# 2021-04-13    B. Ulmann   Initial implementation
#
#  This is a work in progress and not (yet) production ready software!
#
# TODO:
# - Take care of data overruns i.e. to long sampling intervals. This will cause
#   an error message from the Teensy which will then corrupt the expected reply
#   during the next command being issued.
#

package TeensyLogger;

=pod

=head1 NAME

TeensyLogger - Perl interface to a simple Teensy 4.1 based data logger.

=head1 VERSION

This document refers to version 0.1 of TeensyLogger

=head1 SYNOPSIS

The module can be used as follows:

    use strict;
    use warnings;

    use lib '.';
    use TeensyLogger;
    use Data::Dumper;

    # Create a new data logger object:
    my $logger = TeensyLogger->new(port => '/dev/cu.usbmodem90408601', timeout => 1100);

    $logger->set_channels(8);           # Set number of channels to 8
    $logger->set_interval(1000);        # Set sampling interval to 1000 microseconds

    print Dumper($logger->status());    # Get status information
    print Dumper($logger->benchmark()); # Benchmark how long one sample will take

    $logger->arm();                     # Prepare for data gathering
    $logger->start();                   # If no external trigger is available, start gathering
    ...
    $logger->stop();                    # Stop data gathering if no external trigger was used
    ...
    $logger->sample();                  # Perform one sampling operation

    my $data = $logger->get_data();     # Read all data gathered so far. The result is 
                                        # an array of arrays.
    print scalar(@$data), " samples read\n";

    # Store data gathered into a file:
    $logger->store_data(filename => 'test.dat', delimiter => ',');

    $logger->reset();                   # Reset the data logger to its initial configuration

=head1 DESCRIPTION

This module implements a simple object oriented interface to the Teensy 4.1
based eight channel data logger. This data logger was developed for use with
analog and hybrid computers but can be used in any environment featuring 
signal levels between -10 V and +10 V (+/-15 V being the absolute permitted 
maximum).

=cut

use strict;
use warnings;

use Carp qw(confess cluck carp);
use Device::SerialPort;
use Time::HiRes qw(usleep);
use File::Temp;

use vars qw($VERSION);
our $VERSION = '0.1';

use constant {
    MAX_CHANNELS => 8,
};

=head1 Function and methods

=head2 new(port => 'port name', timeout => timeout in milliseconds)

This function generates a new TeensyLogger object. It requires the specification
of the USB port to be used to communicate with the device. If a timeout value
is omitted, a default communications timeout of 1 second is assumed.

=cut

sub new {
    my ($class, %conf) = @_;

    my $port = Device::SerialPort->new($conf{port}) 
        or confess "Unable to connect to USB port: $!\n";

    my $object = bless({
        port    => $port,
        timeout => defined($conf{timeout}) ? $conf{timeout} : 1000,
    }, $class);

    return $object;
}

=head2 arm()

The method arm() arms the data logger so that it will start data gathering
when either told so explicitly by calling the method start() or by an 
external trigger signal which should be the default case.

=cut

sub arm {
    my ($self, $value) = @_;
    $self->{port}->write('arm');
    my $response = get_response($self);
    confess "Unexpected response >>$response<<\n" if $response !~ 'Armed';
}

=head2 benchmark()

The benchmark() method performs a sampling benchmark based on the number
of channels currently configured and returns a reference to a hash which 
in turn contains the keys 'time' and 'channels'. The time-entry contains
the number of microseconds required for a single sample operation while
'channel' returns the number of channels which were used for this particular
benchmark run.

=cut

sub benchmark {
    my ($self) = @_;
    $self->{port}->write('benchmark');
    my $response = get_response($self);
    my ($time, $channels) = $response =~ /^\s*(\d+\.\d+) us.*\@ (\d+)/;
    return {time => $time, channels => $channels};
}

=head2 get_data()

The get_data() method reads data from the data logger and returns a
reference to an array containing array references.

=cut

sub get_data {
    my ($self) = @_;
    $self->{port}->write('dump');
    my $response = get_response($self);
    confess "Unexpted response >>$response<<\n" unless $response =~ /^\d+ samples$/;
    my ($samples) = $response =~ /^(\d+)\s/;
    my @data;
    for (1 .. $samples) {
        my $sample = get_response($self);
        my @values = split(/\t/, $sample);
        push(@data, \@values);
    }
    $self->{data} = \@data;
    return \@data;
}

=head2 plot(title => '...', terminal => '...', 
            output => '...', yrange => '...',
            xrange = '...', columns => '..., ..., ...')

plot() uses gnuplot (which must be installed and be found in the path variable!)
to plot data previously gathered. All parameters are optional:

title can be used to specify the title of the overall plot.

terminal may be used to specify a specific output terminal such as xterm or postscript.

output can be used to direct the gnuplot output into a file.

yrange and xrange expect an argument like '[100:200]' and limit the yrange/xrange of the plot.

columns expects a comma separated string like '..., ..., ...'. The individual entries
are used to label the plot lines in the output graph. If no column names are specified
the respective input channel numbers (1 .. 8) will be used instead.

=cut

sub plot {
    my ($self, %conf) = @_;
    confess "No data to store!\n" unless $self->{data};

    my $data_handle = File::Temp->new(UNLINK => 0, SUFFIX => '.dat');
    my $data_file   = $data_handle;
    print $data_handle join("\t", @$_), "\n" for @{$self->{data}};
    close($data_handle);
    my $channels = scalar(@{$self->{data}[0]});

    my $control_handle = File::Temp->new(UNLINK => 0, SUFFIX => '.ctrl');
    my $control_file   = $control_handle;   # It's a kind of magic... ;-)

    if (defined($conf{title})) {
        my $title = $conf{title};
        $title =~ s/^\s+//;
        $title =~ s/_/\\_/g;
        $title =~ s/\s+\n?$//;
        print $control_handle "set title '$title'\n";
    }

    print $control_handle "set terminal $conf{terminal}\n" if exists $conf{terminal};
    print $control_handle "set output \"$conf{output}\"\n" if exists $conf{output};
    print $control_handle "set yrange [$conf{yrange}{0}:$conf{yrange}{1}]\n" if exists $conf{yrange};
    print $control_handle "set xrange [$conf{xrange}{0}:$conf{xrange}{1}]\n" if exists $conf{xrange};

    my @columns = 1 .. 8;
    if (defined($conf{columns})) {
        my @elements = split(/\s*,\s*/, $conf{columns});
        $columns[$_] = $elements[$_] for 0 .. @elements - 1;
    }

    print $control_handle 
        'plot ', join(', ', map{ "'$data_file' u $_ w l title '$columns[$_ - 1]'" }(1 .. $channels)), "\n";
    close($control_handle);

    system("gnuplot $control_file");
    unlink($control_file);
    unlink($data_file);
}

=head2 reset()

Calling the reset() method resets the data logger to its initial
configuration with respect to the number of channels, sampling 
interval etc.

=cut

sub reset {
    my ($self) = @_;
    $self->{port}->write('reset');
    my $response = get_response($self);
    confess "Could not reset data logger: >>$response<<\n" 
        unless $response =~ /Reset/;
    $self->{data} = undef;
}

=head2 sample()

The sample() method performs a single sampling operation.

=cut

sub sample {
    my ($self, $value) = @_;
    $self->{port}->write('sample');
    my $response = get_response($self);
    confess "Unexpected response >>$response<<\n" if $response !~ /Sampled/;
}

=head2 set_channels(value)

set_channels(value) sets the number of channels to be sampled. The number of 
channels must be greater than zero and less or equal to eight.

=cut

sub set_channels {
    my ($self, $value) = @_;
    confess "Number of channels >>$value<< out of range (must be > 0 and <= " . MAX_CHANNELS . ")!\n" 
        if $value < 1 or $value > MAX_CHANNELS;
    $self->{port}->write("channels=$value");
    my $response = get_response($self);
    confess "Could not set number of channels to $value: >>$response<<\n"
        unless $response =~ /channels=$value/;
}

=head2 set_interval(value)

Calling set_interval(value) sets the interval between two consecutive samples
to the specified value in microseconds.

=cut

sub set_interval {
    my ($self, $value) = @_;
    confess "Interval must be a positive number of microseconds: >>$value<<!\n" if $value < 1;
    $self->{port}->write("interval=$value");
    my $response = get_response($self);
    confess "Could not set interval to $value: >>$response<<\n"
        unless $response =~ /interval=$value/;
}

=head2 set_oversampling(value)

Typically, the data logger samples every data point once. To smooth the 
resulting data, it can be configured to perform oversampling by calling
this method once. The value specified is interpreted as exponent of 2,
i.e. calling set_oversampling(2) will result in 2 ** 2 = 4 samples being
read per data point which are then averaged to give the actual data 
point. Note that oversampling slows down the data sampling considerably
and also introduces increased delay between successive channels. Thus it
should be used with caution!

=cut

sub set_oversampling {
    my ($self, $value) = @_;
    confess "The oversampling value must be >= 0!\n" if $value < 0;
    carp    "Setting oversampling to values > 3 is maybe not a good idea!\n" if $value > 3;
    
    $self->{port}->write("oversampling=$value");
    my $response = get_response($self);
    confess "Could not set oversampling to $value: >>$response<<\n"
         unless $response =~ /oversampling=$value/;
}

=head2 set_max_samples(value)

Using the method set_max_samples(...) it is possible to limit the maximum 
number of samples taken by the data logger. The value must be, of course,
greater than zero.

=cut

sub set_max_samples {
    my ($self, $value) = @_;
    confess "The maximum number of samples must be > 0!\n" if $value < 1;
    
    $self->{port}->write("ms=$value");
    my $response = get_response($self);
    confess "Could not set maximum number of samples to $value: >>$response<<\n"
         unless $response =~ /ms=$value/;
}

=head status()

The method status() returns a reference to a hash containing the current
status and configuration settings of the data logger.

=cut

sub status {
    my ($self, $value) = @_;
    $self->{port}->write('status');
    my $response = get_response($self);
    $response =~ s/^\s+//;
    my %status;
    for my $pair (split(/\s*,\s*/, $response)) {
        my ($name, $value) = split(/\s*=\s*/, $pair);
        $status{$name} = $value;
    }
    return \%status;
}

=head2 start()

Calling start() will start data logging. This method should not be used
under normal circumstances as an external trigger signal allows for much
tighter timing control. 

=cut

sub start {
    my ($self, $value) = @_;
    $self->{port}->write('start');
    my $response = get_response($self);
    confess "System was not armed!\n" if $response =~ /Not armed/;
    confess "Unexpected response >>$response<<\n" if $response !~ 'Started';
}

=head2 stop()

The stop() method stops a currently running data logging operation or
disarms the data logger if no previous trigger signal has been received
or start() has not been called prior to this. It returns a character
string which will be either "Stopped" or "Disarmed" depending on the 
state of the data logger.

=cut

sub stop {
    my ($self, $value) = @_;
    $self->{port}->write('stop');
    my $response = get_response($self);
    $response =~ s/^\s+//;
    confess "Unexpected response >>$response<<\n" if $response ne 'Stopped' and $response ne 'Disarmed';
    return $response;
}

=head2 store_data(filename => '...', delimiter => '...', header => '...')

Calling store_data(...) stores all data gathered so far in a file 
which name is specified as the filename. The optional parameter
'delimiter' can be used to specify a user defined delimiter character 
sequence. The default delimiter character is ';'. If the optional
header-argument is specified, its value character string will be 
written as header line to the data file.

store_data(...) requires that get_data() has been called before!

=cut

sub store_data {
    my ($self, %conf) = @_;
    confess "No data to store!\n"      unless $self->{data};
    confess "No filename specified!\n" unless $conf{filename};
    my $delimiter = defined($conf{delimiter}) ? $conf{delimiter} : ';';
    open(my $handle, '>', $conf{filename}) or confess "Could not open >>$conf{filename}<<: $!\n";
    print $handle "$conf{header}\n" if defined($conf{header});
    print $handle join($delimiter, @$_), "\n" for @{$self->{data}};
    close($handle);
}

=head2 get_response()

The method get_response() waits for a response (a single line) from the 
Teensy 4.1 based data logger. It is normally used only by the routines
of this module. The response is returned as a character string.

=cut

sub get_response {
    my ($self) = @_;
    my $timeout = $self->{timeout};
    do {
        my $response = $self->{port}->lookfor();
        return $response if $response;
        $timeout--;
        usleep(1000);
    } while $timeout;
}

return 1;
