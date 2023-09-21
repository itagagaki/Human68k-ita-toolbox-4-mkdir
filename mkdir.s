* mkdir - make directory
*
* Itagaki Fumihiko  9-Jul-91  Create.
* 1.0
* Itagaki Fumihiko 22-Aug-92  strip_excessive_slashes
* Itagaki Fumihiko 17-Sep-92  非再帰化、mkdir -p foo/../bar/baz が可能。
* Itagaki Fumihiko 24-Sep-92  ドライブを予め検査するのはやめた。
*                             どうしたって完全にはチェックできないので。
* 1.1
* Itagaki Fumihiko 06-Nov-92  strip_excessive_slashesのバグfixに伴う改版。
* 1.2
* Itagaki Fumihiko 10-Nov-92  -p で [?:][/] をスキップする
* 1.3
*
* Usage: mkdir [ -p ] <パス名> ...

.include doscall.h
.include error.h
.include limits.h
.include stat.h
.include chrcode.h

.xref DecodeHUPAIR
.xref issjis
.xref strlen
.xref strfor1
.xref headtail
.xref cat_pathname
.xref strip_excessive_slashes

STACKSIZE	equ	256

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
		movea.l	a0,a1
		bsr	strfor1
		exg	a0,a1				*  A1 : 次の引数
		move.l	a1,-(a7)
		bsr	strip_excessive_slashes
		bsr	mkdir
		movea.l	(a7)+,a0
		subq.l	#1,d7
		bne	loop
exit_program:
		move.w	d6,-(a7)
		DOS	_EXIT2

bad_option:
		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
		bra	usage

too_few_args:
		lea	msg_too_few_args(pc),a0
		bsr	werror_myname_and_msg
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

insufficient_memory:
		lea	msg_no_memory(pc),a0
		bsr	werror_myname_and_msg
		moveq	#3,d6
		bra	exit_program
*****************************************************************
mkdir:
		tst.b	d5
		beq	mkdir_one
****************
		movea.l	a0,a1
		tst.b	(a1)
		beq	make_path_check_root

		cmpi.b	#':',1(a1)
		bne	make_path_check_root

		addq.l	#2,a1
make_path_check_root:
		cmpi.b	#'/',(a1)
		beq	make_path_skip_root

		cmpi.b	#'\',(a1)
		bne	make_path_loop
make_path_skip_root:
		addq.l	#1,a1
make_path_loop:
		move.b	(a1)+,d0
		beq	make_path_find_slash_done

		cmp.b	#'/',d0
		beq	make_path_find_slash_done

		cmp.b	#'\',d0
		beq	make_path_find_slash_done

		bsr	issjis
		bne	make_path_loop

		move.b	(a1)+,d0
		bne	make_path_loop
make_path_find_slash_done:
		move.b	d0,d1
		clr.b	-(a1)
		bsr	is_directory
		bmi	make_path_too_long_path
		bne	make_path_next

		bsr	mkdir_one
		bmi	mkdir_return
make_path_next:
		move.b	d1,(a1)+
		bne	make_path_loop

		rts

make_path_too_long_path:
		moveq	#2,d6
		bsr	werror_myname_and_msg
		lea	msg_too_long_pathname(pc),a0
		bra	werror
****************
mkdir_one:
		move.l	a0,-(a7)
		DOS	_MKDIR
		addq.l	#4,a7
		tst.l	d0
		bpl	mkdir_return
mkdir_error:
		bsr	werror_myname
		cmp.l	#ENODIR,d0
		beq	mkdir_fail_nodir

		move.l	a0,-(a7)
		lea	msg_directory(pc),a0
		bsr	werror
		movea.l	(a7),a0
		bsr	werror
		lea	msg_failed(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		bra	mkdir_fail_perror

mkdir_fail_nodir:
		move.l	d0,-(a7)
		bsr	headtail
		move.l	(a7)+,d0
		bsr	werror_2
mkdir_fail_perror:
		bsr	perror				*  ここで D6.L に 2 がセットされる
		tst.l	d0
mkdir_return:
		rts
*****************************************************************
* is_directory - 名前がディレクトリであるかどうかを調べる
*
* CALL
*      A0     名前
*
* RETURN
*      D0.L   名前/*.* が長すぎるならば -1．
*             そうでなければ，名前がディレクトリならば 1，さもなくば 0
*
*      CCR    TST.L D0
*****************************************************************
is_directory:
		movem.l	a0-a3,-(a7)
		tst.b	(a0)
		beq	is_directory_false

		movea.l	a0,a1
		lea	pathname_buf(pc),a0
		lea	dos_wildcard_all(pc),a2
		bsr	cat_pathname
		bmi	is_directory_return

		move.w	#MODEVAL_ALL,-(a7)		*  すべてのエントリを検索する
		move.l	a0,-(a7)
		pea	filesbuf(pc)
		DOS	_FILES
		lea	10(a7),a7
		tst.l	d0
		bpl	is_directory_true

		cmp.l	#ENOFILE,d0
		beq	is_directory_true
is_directory_false:
		moveq	#0,d0
		bra	is_directory_return

is_directory_true:
		moveq	#1,d0
is_directory_return:
		movem.l	(a7)+,a0-a3
		rts
*****************************************************************
perror:
		movem.l	d0/a0,-(a7)
		not.l	d0		* -1 -> 0, -2 -> 1, ...
		cmp.l	#25,d0
		bls	perror_2

		moveq	#0,d0
perror_2:
		lea	perror_table(pc),a0
		lsl.l	#1,d0
		move.w	(a0,d0.l),d0
		bmi	perror_4

		lea	sys_errmsgs(pc),a0
		lea	(a0,d0.w),a0
		bsr	werror
perror_4:
		lea	msg_newline(pc),a0
		bsr	werror
		movem.l	(a7)+,d0/a0
		moveq	#2,d6
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
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
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## mkdir 1.3 ##  Copyright(C)1992 by Itagaki Fumihiko',0

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

sys_errmsgs:
msg_nodir:		dc.b	': このようなディレクトリはありません',0
msg_bad_name:		dc.b	'; 名前が無効です',0
msg_bad_drive:		dc.b	'; ドライブの指定が無効です',0
msg_write_disabled:	dc.b	'; 書き込みが許可されていません',0
msg_directory_exists:	dc.b	'; すでに存在しています',0
msg_directory_full:	dc.b	'; ディレクトリが満杯です',0
msg_disk_full:		dc.b	'; ディスクが満杯です',0

msg_myname:		dc.b	'mkdir: ',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_directory:		dc.b	'ディレクトリ“',0
msg_failed:		dc.b	'”の作成に失敗しました',0
msg_too_long_pathname:	dc.b	': パス名が長過ぎます',CR,LF,0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_too_few_args:	dc.b	'引数が足りません',0
msg_usage:		dc.b	CR,LF,'使用法:  mkdir [-p] [-] <パス名> ...'
msg_newline:		dc.b	CR,LF,0
dos_wildcard_all:	dc.b	'*.*',0
*****************************************************************
.bss
.even
filesbuf:	ds.b	STATBUFSIZE
pathname_buf:	ds.b	MAXPATH+1
.even
		ds.b	STACKSIZE
.even
stack_bottom:
*****************************************************************

.end start
