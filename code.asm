section .data
header_ok db "HTTP/1.1 200 OK", 13, 10 ; 13, 10 is \r\n
header_ok_len equ $ - header_ok
header_content_type db "Content-Type: "
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
response_internal_se db "HTTP/1.1 500 Internal Server Error", 13, 10
                     db "Content-Type: text/plain", 13, 10
                     db "Content-Length: 25", 13, 10
                     db 13, 10
                     db "500 Internal Server Error"
response_internal_se_len equ $ - response_internal_se

ct_text_html db "text/html", 13, 10
ct_text_html_len equ $ - ct_text_html
ct_text_css db "text/css", 13, 10
ct_text_css_len equ $ - ct_text_css
ct_text_js db "text/javascript", 13, 10
ct_text_js_len equ $ - ct_text_js
ct_img_png db "image/png", 13, 10
ct_img_png_len equ $ - ct_img_png
ct_img_jpg db "image/jpeg", 13, 10
ct_img_jpg_len equ $ - ct_img_jpg
ct_video_mp4 db "video/mp4", 13, 10
ct_video_mp4_len equ $ - ct_video_mp4
ct_app_pdf db "application/pdf", 13, 10
ct_app_pdf_len equ $ - ct_app_pdf

ct_text_plain db "text/plain", 13, 10
ct_text_plain_len equ $ - ct_text_plain

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
fstat_buf resb 144
content_len_buf resb 20
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
        mov rsi, 128 ; max pending connections
        syscall ; end of listen()

        .client_loop:
                mov rax, 43 ; accept()
                mov rdi, r12 ; sock_fd
                xor rsi, rsi
                xor rdx, rdx
                syscall ; end of accept()
                test rax, rax
                js .client_loop
                mov r13, rax ; store the client_fd returned from accept()

                call process_request
                test r13, r13
                jz .client_loop

                lea rdi, [rel response_buf]
                mov rbx, rdi ; save start of buffer

                ; prepare response headers
                lea rsi, [rel header_ok] 
                mov rcx, header_ok_len
                rep movsb ; copy response code
                lea rsi, [rel header_content_type]
                mov rcx, header_content_type_len
                rep movsb ; copy content type
                call get_mime_type
                mov rsi, rax
                rep movsb ; add appropriate MIME type
                lea rsi, [rel header_content_length]
                mov rcx, header_content_length_len
                rep movsb ; copy content length header
                lea rsi, [rel content_len_buf]
                mov rcx, r11 ; from int_to_string
                xor r11, r11
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

                mov rbx, r15 ; copy size for loop
                .sendfile:
                        mov rax, 40 ; sendfile()
                        mov rdi, r13 ; client_fd
                        mov rsi, r14 ; file's fd
                        xor rdx, rdx ; 0 offset (send whole file)
                        mov r10, rbx ; file size
                        syscall ; end of sendfile()

                        test rax, rax
                        jle .sf_done

                        sub rbx, rax
                        jnz .sendfile
                .sf_done:
                xor r15, r15

                mov rax, 3 ; close()
                mov rdi, r14 ; file's fd
                syscall
                xor r14, r14

                mov rax, 3 ; close()
                mov rdi, r13 ; client_fd
                syscall ; end of close()
                xor r13, r13 ; clear the stale client_fd

                jmp .client_loop
        
        mov rax, 60 ; exit()
        mov rdi, 0
        syscall

get_mime_type:
        lea rsi, [rel filename_buf]
        .find_dot:
                mov al, [rsi]
                test al, al
                je error_handler
                cmp al, '.' ; search for dot
                je .fd_done
                inc rsi 
                jmp .find_dot 
        .fd_done:
                cmp dword [rsi], 0x00736a2e ; .js
                je .javascript
                inc rsi
        cmp dword [rsi], 0x6c6d7468 ; html
        je .html
        cmp dword [rsi], 0x00737363 ; css
        je .css
        cmp dword [rsi], 0x00676e70 ; png
        je .png
        cmp dword [rsi], 0x6765706a ; jpeg
        je .jpeg
        cmp dword [rsi], 0x0067706a ; jpg
        je .jpeg
        cmp dword [rsi], 0x0034706d ; mp4
        je .mp4
        cmp dword [rsi], 0x00666470 ; pdf
        je .pdf

        lea rax, [rel ct_text_plain]
        mov rcx, ct_text_plain_len
        ret

        .html:
                lea rax, [rel ct_text_html]
                mov rcx, ct_text_html_len
                ret
        .css:
                lea rax, [rel ct_text_css]
                mov rcx, ct_text_css_len
                ret
        .javascript:
                lea rax, [rel ct_text_js]
                mov rcx, ct_text_js_len
                ret
        .png:
                lea rax, [rel ct_img_png]
                mov rcx, ct_img_png_len
                ret
        .jpeg:
                lea rax, [rel ct_img_jpg]
                mov rcx, ct_img_jpg_len
                ret
        .mp4:
                lea rax, [rel ct_video_mp4]
                mov rcx, ct_video_mp4_len
                ret
        .pdf:
                lea rax, [rel ct_app_pdf]
                mov rcx, ct_app_pdf_len
                ret

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
        .get_file_size:
                mov rax, 5 ; fstat()
                mov rdi, r14 ; file's fd
                lea rsi, [rel fstat_buf]
                syscall ; end of fstat()
                test rax, rax
                js .error_handler
                mov r15, qword [rel fstat_buf + 48] ; 48 is the offset before you reach st_size

                mov rax, r15
                lea rdi, [rel content_len_buf]
                call int_to_string
                mov r11, rax ; save the int_to_string return
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
        mov rax, 1
        mov rdi, 2
        lea rsi, [rel err_msg]
        mov rdx, err_len
        syscall

        mov rax, 1
        mov rdi, r13
        lea rsi, [rel response_bad_request]
        mov rdx, response_bad_request_len
        syscall

        cmp r14, 0
        je .skip_close
        mov rax, 3
        mov rdi, r14
        syscall
        xor r14, r14
.skip_close:
        mov rax, 3
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
        lea rsi, [rel response_internal_se]
        mov rdx, response_internal_se_len
        syscall
        
        mov rax, 3 ; close()
        mov rdi, r13
        syscall
        xor r13, r13

        mov rax, 3
        mov rdi, r14
        syscall
        xor r14, r14 ; file fd
        jmp _start.client_loop
