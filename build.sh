#!/bin/sh
set -e
trap 'rm -f server.o' EXIT
nasm -f elf64 code.asm -o server.o
ld server.o -o server
