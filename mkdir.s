* mkdir - make directory
*
* Itagaki Fumihiko  9-Jul-91  Create.
*
* Usage: mkdir [ -p ] <パス名> ...

.include doscall.h
.include error.h
.include chrcode.h

.xref DecodeHUPAIR
.xref strlen
.xref strfor1
.xref headtail
.xref drvchkp

STACKSIZE	equ	2048

.text
start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	stack_bottom(pc),a7		*  A7 := スタックの底
		DOS	_GETPDB
		movea.l	d0,a0				*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
	*  引数をデコードし，解釈する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		sf	d5				*  D5.B : -p フラグ
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		beq	decode_opt_done
decode_opt_loop2:
		cmp.b	#'p',d0
		bne	bad_option

		st	d5
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_opt_done:
		tst.l	d7
		beq	too_few_args

		moveq	#0,d6				*  D6.W : エラー・コード
loop:
		movea.l	a0,a2
		bsr	strfor1
		exg	a0,a2				*  A2 : 次の引数

		bsr	drvchkp
		bmi	fail

		bsr	mkdir
		bpl	next
fail:
		move.l	a0,-(a7)
		bsr	werror_myname
		cmp.l	#ENODIR,d0
		beq	fail_nodir

		lea	msg_directory(pc),a0
		bsr	werror
		movea.l	(a7),a0
		bsr	werror
		lea	msg_failed(pc),a0
		bsr	werror
		bra	fail_perror

fail_nodir:
		movea.l	(a7),a0
		move.l	d0,-(a7)
		bsr	headtail
		move.l	(a7)+,d0
		bsr	werror_2
fail_perror:
		bsr	perror
		movea.l	(a7)+,a0
		moveq	#2,d6
next:
		movea.l	a2,a0
		subq.l	#1,d7
		bne	loop
exit_program:
		move.w	d6,-(a7)
		DOS	_EXIT2


bad_option:
		bsr	werror_myname
		lea	msg_illegal_option(pc),a0
		bsr	werror
		move.w	d0,-(a7)
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		bra	usage

too_few_args:
		bsr	werror_myname
		lea	msg_too_few_args(pc),a0
		bsr	werror
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

insufficient_memory:
		bsr	werror_myname
		lea	msg_no_memory(pc),a0
		bsr	werror
		moveq	#3,d6
		bra	exit_program
*****************************************************************
perror:
		not.l	d0		* -1 -> 0, -2 -> 1, ...
		cmp.l	#25,d0
		bls	perror_2

		cmp.l	#256,d0
		blo	perror_1

		sub.l	#256,d0
		cmp.l	#4,d0
		bhi	perror_1

		lea	perror_table_2(pc),a0
		bra	perror_3

perror_1:
		moveq	#25,d0
perror_2:
		lea	perror_table(pc),a0
perror_3:
		lsl.l	#1,d0
		move.w	(a0,d0.l),d0
		bmi	perror_4

		lea	sys_errmsgs(pc),a0
		lea	(a0,d0.w),a0
		bsr	werror
perror_4:
		lea	msg_newline(pc),a0
		bra	werror
*****************************************************************
werror_myname:
		lea	msg_myname(pc),a0
werror:
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1
werror_2:
		subq.l	#1,a1
		move.l	d0,-(a7)
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		move.l	(a7)+,d0
		rts
*****************************************************************
mkdir:
		movem.l	d1/a1,-(a7)

	*  目的のディレクトリを作ってみる

		bsr	do_mkdir
		bpl	mkdir_return			*  成功

		tst.b	d5				*  -p が指定されて
		beq	mkdir_return			*  いないならば失敗とする

		cmp.l	#ENODIR,d0			*  「パス名の途中のディレクトリが無い」
		bne	mkdir_return			*  以外ならば失敗

	*  パス名の途中のディレクトリが無い ... まず親ディレクトリを作る

		move.l	d0,-(a7)
		bsr	headtail
		move.l	(a7)+,d0
		cmpa.l	a0,a1
		beq	mkdir_return			*  目的のディレクトリに親は無い

		move.b	-(a1),d1
		cmp.b	#'/',d1
		beq	mkdir_recurse

		cmp.b	#'\',d1
		bne	mkdir_return			*  目的のディレクトリに親は無い
mkdir_recurse:
		clr.b	(a1)
		bsr	mkdir		**  再帰  **
		bmi	mkdir_return			*  親の作成に失敗

	*  親ディレクトリの作成は成功した ... いよいよ目的のディレクトリを作る

		move.b	d1,(a1)
		bsr	do_mkdir
mkdir_return:
		movem.l	(a7)+,d1/a1
		tst.l	d0
		rts
*****************************************************************
do_mkdir:
		move.l	a0,-(a7)
		DOS	_MKDIR
		addq.l	#4,a7
		move.l	d0,d3
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## mkdir 1.0 ##  Copyright(C)1992 by Itagaki Fumihiko',0

.even
perror_table:
	dc.w	-1					*   0 ( -1)
	dc.w	-1					*   1 ( -2)
	dc.w	msg_nodir-sys_errmsgs			*   2 ( -3)
	dc.w	-1					*   3 ( -4)
	dc.w	-1					*   4 ( -5)
	dc.w	-1					*   5 ( -6)
	dc.w	-1					*   6 ( -7)
	dc.w	-1					*   7 ( -8)
	dc.w	-1					*   8 ( -9)
	dc.w	-1					*   9 (-10)
	dc.w	-1					*  10 (-11)
	dc.w	-1					*  11 (-12)
	dc.w	msg_bad_name-sys_errmsgs		*  12 (-13)
	dc.w	-1					*  13 (-14)
	dc.w	msg_bad_drive-sys_errmsgs		*  14 (-15)
	dc.w	-1					*  15 (-16)
	dc.w	-1					*  16 (-17)
	dc.w	-1					*  17 (-18)
	dc.w	msg_write_disabled-sys_errmsgs		*  18 (-19)
	dc.w	msg_directory_exists-sys_errmsgs	*  19 (-20)
	dc.w	-1					*  20 (-21)
	dc.w	-1					*  21 (-22)
	dc.w	msg_disk_full-sys_errmsgs		*  22 (-23)
	dc.w	msg_directory_full-sys_errmsgs		*  23 (-24)
	dc.w	-1					*  24 (-25)
	dc.w	-1					*  25 (-26)

.even
perror_table_2:
	dc.w	msg_bad_drivename-sys_errmsgs		* 256 (-257)
	dc.w	msg_no_drive-sys_errmsgs		* 257 (-258)
	dc.w	msg_no_media_in_drive-sys_errmsgs	* 258 (-259)
	dc.w	msg_media_set_miss-sys_errmsgs		* 259 (-260)
	dc.w	msg_drive_not_ready-sys_errmsgs		* 260 (-261)

sys_errmsgs:
msg_nodir:		dc.b	': このようなディレクトリはありません',0
msg_bad_name:		dc.b	'; 名前が無効です',0
msg_bad_drive:		dc.b	'; ドライブの指定が無効です',0
msg_write_disabled:	dc.b	'; 書き込みが許可されていません',0
msg_directory_exists:	dc.b	'; すでに存在しています',0
msg_directory_full:	dc.b	'; ディレクトリが満杯です',0
msg_disk_full:		dc.b	'; ディスクが満杯です',0
msg_bad_drivename:	dc.b	'; ドライブ名が無効です',0
msg_no_drive:		dc.b	'; ドライブがありません',0
msg_no_media_in_drive:	dc.b	'; ドライブにメディアがセットされていません',0
msg_media_set_miss:	dc.b	'; ドライブにメディアが正しくセットされていません',0
msg_drive_not_ready:	dc.b	'; ドライブの準備ができていません',0

msg_myname:		dc.b	'mkdir: ',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_directory:		dc.b	' ディレクトリ "',0
msg_failed:		dc.b	'" の作成に失敗しました',0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_too_few_args:	dc.b	'引数が足りません',0
msg_usage:		dc.b	CR,LF,'使用法:  mkdir [-p] [-] <パス名> ...'
msg_newline:		dc.b	CR,LF,0
*****************************************************************
.bss
.even
		ds.b	STACKSIZE
.even
stack_bottom:
*****************************************************************

.end start
