#This code contains methods for flow generation and result recording.
# the total (theoretical) load in the bottleneck link
set rho 0.8
puts "rho = $rho"
# Filetransfer parameters
set mfsize 500
# bottleneck bandwidth, required for setting the load
set bnbw 10000000
#maximum number of tcps
set nof_tcps 100
#number of RTT classes
set nof_classes 4
#load divided evenly between RTT classes
set rho_cl [expr $rho/$nof_classes]

# not set in original code, added a random value for this variable
set mpktsize 500

puts "rho_cl=$rho_cl, nof_classes=$nof_classes"
set mean_intarrtime [expr ($mpktsize+40)8.0$mfsize/($bnbw*$rho_cl)]
#flow interarrival time
puts "1/la = $mean_intarrtime"
for {set ii 0} {$ii < $nof_classes} {incr ii} {
    set delres($ii) {}
    #contains the delay results for each class

    set nlist($ii) {}
    #contains the number of active flows as a function of time

    set freelist($ii) {}
    #contains the free flows

    set reslist($ii) {}
    #contains information of the reserved flows

    set ftp($ii) {}

}
Agent/TCP instproc done {} {
    global nssim freelist reslist ftp rng mfsize mean_intarrtime nof_tcps simstart simend delres nlist
    #the global variables nssim (ns simulator instance), ftp (application),
    #rng (random number generator), simstart (start time of the simulation) and
    #simend (ending time of the simulation) have to be created by the user in
    #the main program
    #flow-ID of the TCP flow
    set flind [$self set fid_]
    #the class is determined by the flow-ID and total number of tcp-sources
    set class [expr int(floor($flind/$nof_tcps))]
    set ind [expr $flind-$class*$nof_tcps]
    lappend nlist($class) [list [$nssim now] [llength $reslist($class)]]
    for {set nn 0} {$nn < [llength $reslist($class)]} {incr nn} {
        set tmp [lindex $reslist($class) $nn]
        set tmpind [lindex $tmp 0]
        if {$tmpind == $ind} {
            set mm $nn
            set starttime [lindex $tmp 1]
        }
    }
    set reslist($class) [lreplace $reslist($class) $mm $mm]
    lappend freelist($class) $ind
    set tt [$nssim now]
    if {$starttime > $simstart && $tt < $simend} {
        lappend delres($class) [expr $tt-$starttime]
    }
    if {$tt > $simend} {
        $nssim at $tt "$nssim halt"
    }
}
proc start_flow {class} {
    global nssim freelist reslist ftp tcp_s tcp_d rng nof_tcps mfsize mean_intarrtime simend
    #you have to create the variables tcp_s (tcp source) and tcp_d (tcp destination)
    set tt [$nssim now]
    set freeflows [llength $freelist($class)]
    set resflows [llength $reslist($class)]
    lappend nlist($class) [list $tt $resflows]
    if {$freeflows == 0} {
        puts "Class $class: At $tt, nof of free TCP sources == 0!!!"
        puts "freelist($class)=$freelist($class)"
        puts "reslist($class)=$reslist($class)"
        exit
    }
    #take the first index from the list of free flows
    set ind [lindex $freelist($class) 0]
    set cur_fsize [expr ceil([$rng exponential $mfsize])]
    # $tcp_s($class,$ind) reset
    # $tcp_d($class,$ind) reset
    [lindex [lindex $ftp $class] $ind] produce $cur_fsize
    set freelist($class) [lreplace $freelist($class) 0 0]
    lappend reslist($class) [list $ind $tt $cur_fsize]
    set newarrtime [expr $tt+[[$rng value] exponential $mean_intarrtime]]
    $nssim at $newarrtime "start_flow $class"
    if {$tt > $simend} {
        $nssim at $tt "$nssim halt"
    }
}

set fmon_bn [$nssim makeflowmon 0]
$nssim attach-fmon [$nssim link $n0 $n5] $fmon_bn

set parr_start 0
set pdrops_start 0

proc record_start {} {
    global fmon_bn nssim parr_start pdrops_start nof_classes
    #you have to create the fmon_bn (flow monitor) in the bottleneck link
    set parr_start [$fmon_bn set parrivals_]
    set pdrops_start [$fmon_bn set pdrops_]
    puts "Bottleneck at [$nssim now]: arr=$parr_start, drops=$pdrops_start"
}

set parr_end 0
set pdrops_end 0

proc record_end {} {
    global fmon_bn nssim parr_start pdrops_start nof_classes
    set parr_start [$fmon_bn set parrivals_]
    set pdrops_start [$fmon_bn set pdrops_]
    puts "Bottleneck at [$nssim now]: arr=$parr_start, drops=$pdrops_start"
}


set nssim [new Simulator]
set tr [open "out.tr" w+]
$nssim trace-all $tr

set ftr [open "out.nam" w+]
$nssim namtrace-all $ftr

#Router
set n0 [$nssim node]

#Nodes
set n1 [$nssim node]
set n2 [$nssim node]
set n3 [$nssim node]
set n4 [$nssim node]

#Destination
set n5 [$nssim node]

$nssim duplex-link $n0 $n1 100Mb 10ms DropTail
$nssim duplex-link $n0 $n2 100Mb 40ms DropTail
$nssim duplex-link $n0 $n3 100Mb 70ms DropTail
$nssim duplex-link $n0 $n4 100Mb 100ms DropTail
$nssim duplex-link $n0 $n5 10Mb 10ms DropTail

$nssim queue-limit $n0 $n1 1000
$nssim queue-limit $n0 $n2 1000
$nssim queue-limit $n0 $n3 1000
$nssim queue-limit $n0 $n4 1000
$nssim queue-limit $n0 $n5 1000


set sinks {}
set tcp0 {}
set tcp1 {}
set tcp2 {}
set tcp3 {}

set class0 {}
set class1 {}
set class2 {}
set class3 {}

for {set i 0} {$i < 400} {incr i} {
    global sinks
    lappend sinks [new Agent/TCPSink]
    $nssim attach-agent $n5 [lindex $sinks $i]
}

for { set i 0 } { $i < 100 } { incr i } {
    global tcp0 ftp sinks class0
    lappend tcp0 [new Agent/TCP/Reno]
    lappend class0 [$nssim node]
    [lindex $tcp0 $i] set window_ 1000
    [lindex $tcp0 $i] set fid_ $i
    $nssim attach-agent [lindex $class0 $i] [lindex $tcp0 $i]
    $nssim connect [lindex $sinks $i] [lindex $tcp0 $i]

    lappend freelist(0) $i

    lappend ftp(0) [new Application/FTP]
    [lindex $ftp(0) $i] set packet_size_ 1460
    [lindex $ftp(0) $i] attach-agent [lindex $tcp0 $i]
}




for {set i 100 } {$i < 200} {incr i} {
    global tcp1 ftp sinks class1
    lappend tcp1 [new Agent/TCP/Reno]
    [lindex $tcp1 [expr $i-100]] set window_ 1000
    [lindex $tcp1 [expr $i-100]] set fid_ $i
    $nssim attach-agent  [lindex $class1 [expr $i-100]] [lindex $tcp1 [expr $i-100]]
    $nssim connect [lindex $sinks $i] [lindex $tcp1 [expr $i-100]]

    lappend freelist(1) [expr $i-100]

    lappend ftp(1) [new Application/FTP]
    [lindex $ftp(1) [expr $i-100]] set packet_size_ 1460
    [lindex $ftp(1) [expr $i-100]] attach-agent [lindex $tcp1 [expr $i-100]]
}


for {set i 200 } {$i < 300} {incr i} {
    global tcp2 ftp sinks class2
    lappend tcp2 [new Agent/TCP/Reno]
    [lindex $tcp2 [expr $i-200]] set window_ 1000
    [lindex $tcp2 [expr $i-200]] set fid_ $i
    $nssim attach-agent [lindex $class2 [expr $i-200]] [lindex $tcp2 [expr $i-200]]
    $nssim connect [lindex $sinks $i] [lindex $tcp2 [expr $i-200]]

    lappend freelist(2) [expr $i-200]

    lappend ftp(2) [new Application/FTP]
    [lindex $ftp(2) [expr $i-200]] set packet_size_ 1460
    [lindex $ftp(2) [expr $i-200]] attach-agent [lindex $tcp2 [expr $i-200]]
}

for {set i 300 } {$i < 400} {incr i} {
    global tcp3 ftp sinks class3
    lappend tcp3 [new Agent/TCP/Reno]
    [lindex $tcp3 [expr $i-300]] set window_ 1000
    [lindex $tcp3 [expr $i-300]] set fid_ $i
    $nssim attach-agent [lindex $class3 [expr $i-300]] [lindex $tcp3 [expr $i-300]]
    $nssim connect [lindex $sinks $i] [lindex $tcp3 [expr $i-300]]

    lappend freelist(3) [expr $i-300]

    lappend ftp(3) [new Application/FTP]

    [lindex $ftp(3) [expr $i-300]] set packet_size_ 1460
    [lindex $ftp(3) [expr $i-300]] attach-agent [lindex $tcp3 [expr $i-300]]
}

set rng [new RNG]

$rng seed 30


# create a random variable that follows the uniform distribution
set loss_random_variable [new RandomVariable/Uniform]
# the range of the random variable;
$loss_random_variable set min_ 0
$loss_random_variable set max_ 100

# create the error model;
set loss_module [new ErrorModel]
#a null agent where the dropped packets go to
$loss_module drop-target [new Agent/Null]
# error rate will then be (0.1 = 10 / (100 - 0));
##Todo: This is to be changed according to p = [0.1,0.5, 1,2,4,5]%
$loss_module set rate_ 0.1
# attach the random variable to loss module;
$loss_module ranvar $loss_random_variable
$nssim lossmodel $loss_module $n0 $n5


start_flow 0
start_flow 1
start_flow 2
start_flow 3