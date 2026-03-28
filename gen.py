#!/usr/bin/env python3

import os
import signal
from scapy.all import *
from netfilterqueue import NetfilterQueue
import argparse
import sys
import threading
import traceback
import time
import random

window_size = 17
edit_times = {}
window_scale = 7
confusion_times = 7
split_number = 7
enable_seq_confusion = False
seq_offset_min = -500
seq_offset_max = 500

def cleanup_edit_times(edit_times):
    while True:
        current_time = time.time()
        for key, value in list(edit_times.items()):
            created_time = value[0]
            if current_time - created_time >= 10:
                try:
                    del edit_times[key]
                except:
                    pass
        time.sleep(10)

def clear_window_scale(ip_layer):
    if ip_layer.haslayer(TCP):
        tcp_layer = ip_layer[TCP]
        tcp_options = tcp_layer.options
        new_options = []
        for i in range(len(tcp_options)):
            if tcp_options[i][0] == 'WScale':
                continue
            new_options.append(tcp_options[i])
        tcp_layer.options = new_options
    return ip_layer

def modify_window(pkt):
    global edit_times
    try:
        ip = IP(pkt.get_payload())
        if ip.haslayer(TCP):
            key = f"{ip.dst}_{ip[TCP].dport}"

            if ip[TCP].flags == "SA":
                edit_times[key] = [time.time(), 1]
                ip = clear_window_scale(ip)
                ip[TCP].window = window_size
                del ip[IP].chksum
                del ip[TCP].chksum
                pkt.set_payload(bytes(ip))

                thread = threading.Thread(target=send_payloads, args=(ip, ))
                thread.start()

            elif ip[TCP].flags == "A":
                if not key in edit_times:
                    edit_times[key] = [time.time(), 1]
                if edit_times[key][1] < split_number:
                    ip[TCP].window = window_size
                else:
                    ip[TCP].window = 28960
                edit_times[key][1] += 1
                del ip[IP].chksum
                del ip[TCP].chksum
                pkt.set_payload(bytes(ip))
    except Exception as e:
        pass
    pkt.accept()

def send_payloads(ip):
    if confusion_times < 1:
        return
    
    src_ip = ip.dst
    dst_ip = ip.src
    sport = ip[TCP].dport
    dport = ip[TCP].sport
    base_seq = ip[TCP].seq
    
    for i in range(1, confusion_times + 1):
        _win_size = window_size
        if i == confusion_times:
            _win_size = 65535
        
        ack_num = base_seq + i
        
        if enable_seq_confusion:
            seq_offset = random.randint(seq_offset_min, seq_offset_max)
            fake_seq = (base_seq + seq_offset) & 0xFFFFFFFF
        else:
            fake_seq = base_seq
        
        ack_packet = IP(src=src_ip, dst=dst_ip) / TCP(
            sport=sport,
            dport=dport,
            flags="A",
            seq=fake_seq,
            ack=ack_num,
            window=_win_size,
            options=[('WScale', window_scale)] + [('NOP', '')] * 5
        )
        send(ack_packet, verbose=False)

def parsearg():
    global window_size
    global window_scale
    global confusion_times
    global split_number
    global enable_seq_confusion
    global seq_offset_min
    global seq_offset_max
    
    parser = argparse.ArgumentParser()
    
    parser.add_argument('-q', '--queue', type=int, help='iptables Queue Num')
    parser.add_argument('-w', '--window_size', type=int, help='Tcp Window Size')
    parser.add_argument('-s', '--window_scale', type=int, help='Tcp Window Scale')
    parser.add_argument('-c', '--confusion_times', type=int, help='confusion_times')
    parser.add_argument('-n', '--split_number', type=int, help='Tcp Split Number')
    
    parser.add_argument('-e', '--enable_seq_confusion', action='store_true')
    parser.add_argument('--seq_offset_min', type=int, default=-500)
    parser.add_argument('--seq_offset_max', type=int, default=500)

    args = parser.parse_args()

    if args.queue is None or args.window_size is None:
        exit(1)

    window_size = args.window_size
    window_scale = args.window_scale if args.window_scale else 7
    confusion_times = args.confusion_times if args.confusion_times else 7
    split_number = args.split_number if args.split_number else 7
    
    enable_seq_confusion = args.enable_seq_confusion
    seq_offset_min = args.seq_offset_min
    seq_offset_max = args.seq_offset_max

    return args.queue

def main():
    thread = threading.Thread(target=cleanup_edit_times, args=(edit_times, ))
    thread.start()
    queue_num = parsearg()
    nfqueue = NetfilterQueue()
    nfqueue.bind(queue_num, modify_window)

    try:
        print("Starting netfilter_queue process...")
        nfqueue.run()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    signal.signal(signal.SIGINT, lambda signal, frame: sys.exit(0))
    main()
