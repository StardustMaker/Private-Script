#!/usr/bin/env python3

import os
import signal
from scapy.all import IP, TCP
from netfilterqueue import NetfilterQueue
import argparse
import sys
import time
import random
import socket
import struct

window_size = 65535
window_scale = 0
confusion_times = 0
enable_seq_confusion = False
seq_offset_min = -500
seq_offset_max = 500

raw_socket = None

def get_raw_socket():
    global raw_socket
    if raw_socket is None:
        raw_socket = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_RAW)
        raw_socket.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)
    return raw_socket

def send_raw_packet(packet_bytes, dst_ip):
    try:
        sock = get_raw_socket()
        sock.sendto(packet_bytes, (dst_ip, 0))
    except:
        pass

def modify_window(pkt):
    try:
        ip = IP(pkt.get_payload())
        if not ip.haslayer(TCP):
            pkt.accept()
            return
        
        tcp = ip[TCP]
        
        if tcp.flags == "SA":
            if window_size > 0:
                tcp.window = window_size
            new_options = []
            for opt in tcp.options:
                if opt[0] == 'WScale':
                    if window_scale > 0:
                        new_options.append(('WScale', window_scale))
                else:
                    new_options.append(opt)
            tcp.options = new_options
            del ip.chksum
            del tcp.chksum
            pkt.set_payload(bytes(ip))
            
            if confusion_times >= 1:
                send_confusion_packet(ip)
        
        pkt.accept()
    except:
        pkt.accept()

def send_confusion_packet(ip):
    try:
        src_ip = ip.dst
        dst_ip = ip.src
        sport = ip[TCP].dport
        dport = ip[TCP].sport
        base_seq = ip[TCP].seq
        
        ack_num = base_seq + 1
        
        if enable_seq_confusion:
            seq_offset = random.randint(seq_offset_min, seq_offset_max)
            fake_seq = (base_seq + seq_offset) & 0xFFFFFFFF
        else:
            fake_seq = base_seq
        
        tcp_header = struct.pack('!HHIIBBHHH',
            sport,
            dport,
            fake_seq,
            ack_num,
            0x50 | 0x08,
            0x10,
            65535,
            0,
            0
        )
        
        ip_header = struct.pack('!BBHHHBBH4s4s',
            0x45,
            0,
            20 + 20,
            random.randint(0, 65535),
            0x4000,
            64,
            6,
            0,
            socket.inet_aton(src_ip),
            socket.inet_aton(dst_ip)
        )
        
        packet = ip_header + tcp_header
        send_raw_packet(packet, dst_ip)
    except:
        pass

def parsearg():
    global window_size
    global window_scale
    global confusion_times
    global enable_seq_confusion
    global seq_offset_min
    global seq_offset_max
    
    parser = argparse.ArgumentParser()
    parser.add_argument('-q', '--queue', type=int, help='iptables Queue Num')
    parser.add_argument('-w', '--window_size', type=int, default=65535, help='Tcp Window Size')
    parser.add_argument('-s', '--window_scale', type=int, default=0, help='Tcp Window Scale')
    parser.add_argument('-c', '--confusion_times', type=int, default=0, help='confusion_times (0=disabled)')
    parser.add_argument('-n', '--split_number', type=int, default=0, help='Tcp Split Number')
    parser.add_argument('-e', '--enable_seq_confusion', action='store_true')
    parser.add_argument('--seq_offset_min', type=int, default=-500)
    parser.add_argument('--seq_offset_max', type=int, default=500)

    args = parser.parse_args()

    if args.queue is None:
        exit(1)

    window_size = args.window_size
    window_scale = args.window_scale
    confusion_times = args.confusion_times
    enable_seq_confusion = args.enable_seq_confusion
    seq_offset_min = args.seq_offset_min
    seq_offset_max = args.seq_offset_max

    return args.queue

def main():
    queue_num = parsearg()
    nfqueue = NetfilterQueue()
    nfqueue.bind(queue_num, modify_window)

    try:
        print("Starting netfilter_queue process...")
        nfqueue.run()
    except KeyboardInterrupt:
        pass
    finally:
        if raw_socket:
            raw_socket.close()

if __name__ == "__main__":
    signal.signal(signal.SIGINT, lambda signal, frame: sys.exit(0))
    main()
