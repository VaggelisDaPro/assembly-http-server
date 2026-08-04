# HTTP Server Written in x86-64 Assembly

A simple static HTTP server written in pure x86-64 assembly, using Linux syscalls exclusively and no libc.

### Highlights

- Pure x86-64 assembly
- No libc
- Linux syscalls only
- Safe file access with `openat2()`
- Automated MIME type checking
- `sendfile()` usage for serving any size file
- ~12 KB executable
- Compiles with NASM and ld

# Project Overview

This project is a simple HTTP server that serves static files. It was made libc-less so it's only ~12KB in size and eliminates any dependency issues that could've occurred.

Since it has no libc and only runs on syscalls, you are able to compile it with `nasm` and run it instantly. Look below for more instructions on how to install.

The server is hosted on `:8080`. Requests on `/` are mapped to `index.html`, so you can use the provided [index.html](./index.html) to test for yourself. All other paths are relative to the server's working directory and are served if the requested file exists. Since it uses `openat2()` to load files, path traversal attacks are more difficult than a naive `open()` implementation. Security testing is welcome, although it hasn't undergone any formal auditing.

> [!NOTE]
> As of 1.1, the server allows to send any size files with the new `sendfile()` implementation, and has automated MIME type checking for a few common objects, such as stylesheets, JavaScript code, PDFs and more.

Obviously, this is not a production grade server, and there are some stuff you should be mindful of:

- Only a few responses are hardcoded in this project, which suffice for what this project is trying to achieve.
- Currently the server is single threaded, meaning it will work on a single client before going to the next one. _I am planning on adding multithreading on the next version of this project._

As of writing, these are some core issues that come to mind, and surely there are a few more, but the project itself is pretty well functioning for its purpose.

## Config

Some values you can tweak for your testing:

1. Port Number
   The port number is stored in network byte order, so any changes will need to be made accordingly. You can change the port number found in line 29.

# AI Usage

AI was only used as a learning aid for this project, and with that I must clarify: There are **no parts of the `code.asm` that was written by AI**, it was all handwritten by me. I personally only used it to understand how registers and syscalls worked, and I have to say that I did in the process of making this project.

# Prerequisites

In order for the compiled server to run, you require Linux 5.6 (2020) or newer as it uses `openat2()` which is only available after that version, although you shouldn't have any issues since modern distributions use a newer version.

Also you will require `nasm` in order to compile the binary, which can be installed with:

```bash
sudo apt install nasm
```

The linker used is `ld` which comes from `binutils` and should be preinstalled on your environment. Should it not be installed, you can install it with:

```bash
sudo apt install binutils
```

## Building & Running

1. Clone the repo.

```bash
git clone https://github.com/VaggelisDaPro/assembly-http-server
```

2. Navigate to the directory and run the [build.sh](./build.sh) file.

```bash
cd ./assembly-http-server/
chmod +x ./build.sh
./build.sh
```

3. Run the server file that was compiled.

```bash
./server
```

Feel free to use the supplied [index.html](./index.html) file so something is displayed at the root.
