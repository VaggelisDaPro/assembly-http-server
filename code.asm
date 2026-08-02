section .data
header_ok db "HTTP/1.1 200 OK", 13, 10 ; 13, 10 is \r\n
header_ok_len equ $ - header_ok
header_content_type db "Content-Type: text/html", 13, 10 
header_content_type_len equ $ - header_content_type
header_content_length db "Content-Length: "
header_content_length_len equ $ - header_content_length

response_not_found db "HTTP/1.1 404 Not Found", 13, 10
                   db "Content-Type: text/plain", 13, 10
                   db "Content-Length: 18", 13, 10
                   db 13, 10
                   db "404 Page not found"
response_not_found_len equ $ - response_not_found
response_bad_request db "HTTP/1.1 400 Bad Request", 13, 10
                     db "Content-Type: text/plain", 13, 10
                     db "Content-Length: 15", 13, 10
                     db 13, 10
                     db "400 Bad Request"
response_bad_request_len equ $ - response_bad_request

err_msg db "An error occured", 10
err_len equ $ - err_msg

crlf db 13, 10

sockaddr:
        dw 2
        dw 0x901F ; port 8080
        dd 0
        dq 0

openat2_how:
        dq 0 ; O_RDONLY
        dq 0 ; mode: 0
        dq 0x0c ; RESOLVE_BENEATH + RESOLVE_NO_SYMLINKS

section .bss
request_buf resb 4096
filename_buf resb 256
file_content_buf resb 8192
content_len_buf resq 1 ; 8 bytes
response_buf resb 256

section .text
global _start

_start:
        mov rax, 41 ; socket()
        mov rdi, 2 ; AF_INET
        mov rsi, 1 ; SOCK_STREAM
        xor rdx, rdx ; 0
        syscall ; end of socket()

        mov r12, rax ; save the sock_fd (that socket() returns)
        mov rax, 49 ; bind()
        mov rdi, r12 ; use the sock_fd
        lea rsi, [rel sockaddr]
        mov rdx, 16
        syscall ; end of bind()
        test rax, rax
        js error_handler

        mov rax, 50 ; listen()
        mov rdi, r12 ; sock_fd
        mov rsi, 1 ; max pending connections
        syscall ; end of listen()

        .loop:
                mov rax, 43 ; accept()
                mov rdi, r12 ; sock_fd
                xor rsi, rsi
                xor rdx, rdx
                syscall ; end of accept()
                test rax, rax
                js .loop
                mov r13, rax ; store the client_fd returned from accept()

                call process_request
                test r13, r13
                jz .loop

                lea rdi, [rel response_buf]
                mov rbx, rdi ; save start of buffer

                ; prepare response headers
                lea rsi, [rel header_ok] 
                mov rcx, header_ok_len
                rep movsb ; copy response code
                lea rsi, [rel header_content_type]
                mov rcx, header_content_type_len
                rep movsb ; copy content type
                lea rsi, [rel header_content_length]
                mov rcx, header_content_length_len
                rep movsb ; copy content length header
                lea rsi, [rel content_len_buf]
                mov rcx, rax ; from int_to_string
                rep movsb
                lea rsi, [rel crlf]
                mov rcx, 2
                rep movsb
                lea rsi, [rel crlf]
                mov rcx, 2
                rep movsb

                mov rdx, rdi
                sub rdx, rbx

                mov rax, 1 ; write()
                mov rdi, r13 ; client_fd
                lea rsi, [rel response_buf]
                syscall ; end of write()

                mov rax, 1 ; write()
                mov rdi, r13 ; client_fd
                lea rsi, [rel file_content_buf]
                mov rdx, r15 ; file length saved from earlier
                syscall ; end of write()
                xor r15, r15

                mov rax, 3 ; close()
                mov rdi, r13 ; client_fd
                syscall ; end of close()
                xor r13, r13 ; clear the stale client_fd

                jmp .loop
        
        mov rax, 60 ; exit()
        mov rdi, 0
        syscall

process_request:
        ; read the request
        mov rax, 0 ; read()
        mov rdi, r13 ; the location of the client_fd
        lea rsi, [rel request_buf] ; allocated memory in .bss to read the request
        mov rdx, 4096 
        syscall ; end of read()
        mov rcx, rax ; total size
        
        .filename_start:
                cmp rcx, 0
                je .error_handler ; no space found in the buffer (reached the end)
                cmp byte [rsi], 0x20
                je .found_space

                inc rsi ; next char
                dec rcx
                jmp .filename_start ; no space found

        .found_space:
                inc rsi ; skip space
                dec rcx
                lea rdi, [rel filename_buf]
                xor rbx, rbx ; clear filename counter

        .read_filename:
                cmp rcx, 0
                je .error_handler ; no second space found in the buffer (reached the end)
                cmp byte [rsi], 0x20
                je .filename_done

                mov al, byte [rsi]
                mov byte [rdi], al

                inc rsi ; next input byte
                inc rdi ; next output pos
                inc rbx ; increment counter
                dec rcx ; remaining bytes

                cmp rbx, 255
                je .error_handler
                jmp .read_filename
                
        .filename_done:
                mov byte [rdi], 0 ; add null terminator

                lea rsi, [rel filename_buf]
                cmp byte [rsi], '/'
                jne .skip_strip

                lea rdi, [rel filename_buf]
                .strip_loop:
                        mov al, [rsi+1]
                        mov [rdi], al
                        inc rsi
                        inc rdi
                        test al, al
                        jnz .strip_loop
                dec rbx
        .skip_strip:
                cmp rbx, 0 ; was the path exactly "/"?
                jne .open_file 

                ; if it reached here, its the root path
                lea rbx, [rel filename_buf]
                mov dword [rbx], 0x65646e69 ; "inde"
                mov dword [rbx+4], 0x74682e78 ; "x.ht"
                mov word [rbx+8], 0x6c6d ; "ml"
                mov byte [rbx+10], 0x00 ; null terminator
                mov rbx, 10
        .open_file:
                mov rax, 437 ; openat2()
                mov rdi, -100 ; AT_FDCWD
                lea rsi, [rel filename_buf]
                lea rdx, [rel openat2_how]
                mov r10, 24 ; size of open_how struct
                syscall

                test rax, rax
                js .error_notfound
                mov r14, rax ; keep the file's fd
        .read_file:
                mov rax, 0 ; read()
                mov rdi, r14 ; file's fd
                lea rsi, [rel file_content_buf]
                mov rdx, 4096
                syscall ; end of read()
                mov r15, rax ; temporarily save file length
                
                mov rax, 3 ; close()
                mov rdi, r14 ; file's fd
                syscall
                xor r14, r14

                mov rax, r15
                lea rdi, [rel content_len_buf]
                call int_to_string
        ret
.error_notfound:
        mov rax, 1 ; write()
        mov rdi, r13 ; client_fd
        lea rsi, [rel response_not_found]
        mov rdx, response_not_found_len
        syscall

        mov rax, 3 ; close()
        mov rdi, r13
        syscall
        xor r13, r13
        ret

.error_handler:
        mov rax, 1 ; write()
        mov rdi, 2 ; std_err
        lea rsi, [rel err_msg]
        mov rdx, err_len
        syscall

        mov rax, 1 
        mov rdi, r13 ; client_fd
        lea rsi, [rel response_bad_request]
        mov rdx, response_bad_request_len
        syscall
        
        mov rax, 3 ; close()
        mov rdi, r13
        syscall
        xor r13, r13
        ret


int_to_string:
        push rbx
        mov rbx, 10
        mov rcx, 0

        .divide_loop:
                xor rdx, rdx ; clear rdx before division
                div rbx ; rdx:rax by rbx (rax = quotient, rdx = remainder)
                add rdx, 48 ; convert remainder to ascii
                push rdx ; save on stack
                inc rcx 
                cmp rax, 0
                jne .divide_loop

                mov r8, rcx
                mov rsi, rdi
        .pop_loop:
                pop rdx
                mov [rsi], dl
                inc rsi
                loop .pop_loop
                mov rax, r8 ; count
                pop rbx
        ret

error_handler:
        mov rax, 1 ; write()
        mov rdi, 2 ; std_err
        lea rsi, [rel err_msg]
        mov rdx, err_len
        syscall

        mov rax, 1 
        mov rdi, r13 ; client_fd
        lea rsi, [rel response_bad_request]
        mov rdx, response_bad_request_len
        syscall
        
        mov rax, 3 ; close()
        mov rdi, r13
        syscall
        xor r13, r13
        jmp _start.loop
