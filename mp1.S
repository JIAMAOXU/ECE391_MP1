
# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0  
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32   

    # Character to draw for an explosion - '@'

	EXPLOSION = 64


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:

	# initialize stack frame
	pushl %ebp                 
	movl %esp, %ebp

	# protect callee-saved registers
	pushl %eax
	pushl %ebx
	pushl %ecx
	pushl %edx
	pushl %esi
	pushl %edi

	# (1) updates the list of missiles (implement this in update_missiles,
	# below, and call it from here).
	# Call function update the list of missles
	call update_missiles

	# (2) Redraw the bases - they may have been overwritten with missiles
	# call redraw_the_bases

	#	(3) Redraw the crosshairs - it may have been overwritten with missiles
	# call redraw_the_crosshairs
	call redraw_the_crosshairs
	popl %edi
    popl %esi
    popl %edx
    popl %ecx
	popl %ebx
	popl %eax
	leave
	ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:

		# load the input into esi
		movl 8(%esp), %esi
		cmpl $0, %esi
		jl error
		cmpl $4, %esi
		jg error
		jmp *jump_table(,%esi,4)

error: 	
		movl $-1, %eax			
		ret

jump_table:
	.long mp1_ioctl_startgame, mp1_ioctl_addmissile
	
	
	


# ----------------- Functions private to this file -------------------

update_missiles:
	# initialize stack frame
	pushl %ebp                 
	movl %esp, %ebp
	# protect callee-saved registers
	pushl %eax
	pushl %ebx
	pushl %ecx
	pushl %edx
	pushl %esi
	pushl %edi
	# place start of missile list into ecx (cursor), and start traversal
	movl mp1_missile_list, %ecx
	# compare ebx with 0 to see if finish the traversal


missle_list_traversal:
	cmpl $0, %ecx
	je traversal_done
	# traversal not done, traversal start
	# low 16 bits of x and y fields determine which of these sub-squares the missile is in
	# high 16 bits of x and y determine the text-mode video location to draw the missile
	# movl 8(%ebp),%ecx

	# load x value into edi
	movl X(%ecx), %edi
	# shift edi right 16 bit to get x position
	shrl $16, %edi

	# BOUND CHECK: x should be [0,24]
	cmpl $0, %edi
	jl erase_missle
	cmpl $24, %edi
	jg erase_missle

	# load y value into edi
	movl Y(%ecx), %esi
	# shift edi right 16 bit to get y position
	shrl $16, %esi

	# BOUND CHECK: y should be [0,80]
	cmpl $0, %esi
	jl erase_missle
	cmpl $79, %esi
	jg erase_missle

	# EXPLOSION CHECK: check if missle is exploded
	cmpl $0, EXPLODED(%ecx)
	jne call_exploded
	
	# DESTINATION CHECK: check if missle reach destination
	cmpl DEST_X (%ecx), %edi
	jne missle_flying
	cmpl DEST_Y (%ecx), %esi
	jne missle_flying

	# missle x and y position same as destination, jump to missle exploded
	jmp call_exploded
	
	popl %edi
	popl %esi
	popl %edx
	popl %ecx
	popl %ebx
	popl %eax
	jmp traversal_done

missle_flying: 
	# initialize stack frame
	pushl %ebp                 
	movl %esp, %ebp
	# not explod, it means that missle if flying
	# update the x and y position based on vx and vy

	# first remove the old missle image
	pushl %eax
	pushl %ecx
	pushl %edx
	# erase missle image
	jmp position_calculation

	# move on to next missile
	movl NEXT (%ecx), %ecx
	popl %edx	
	popl %ecx
	popl %eax
	jmp missle_list_traversal
position_calculation: 
	# initialize stack frame
	pushl %ebp
	movl %esp, %ebp
	# draw the new missle image,update the new x, y information back to register
	# update X
	pushl %eax
	pushl %ebx
	pushl %ecx
	pushl %edx
	pushl %esi
	pushl %edi
	# edi stores VX
	movl VX(%ecx), %edi 
	# update X
	addl X(%ecx), %edi
	movl %edi, X(%ecx)
	shrl $16, %edi

	# esi stores VY
	movl VY(%ecx), %esi 
	# update Y
	addl Y(%ecx), %esi	
	movl %esi, Y(%ecx)
	shrl $16, %esi
	
	position_onscreen:
	# memory offset = x*2 + y*80*2
	# calculate x*2
	imull $2, %edi, %edi
	# calculate y*80*2
	imull $80, %esi, %esi
	imull $2, %esi, %esi
	# add  x*2 and y*80*2
	addl %esi, %edi
	# store memory offset in eax
	movl %edi, %eax
	# draw missle 
	movb C(%ecx), %cl
	pushl %ecx
	call mp1_poke
	popl %ecx

	popl %edi
	popl %esi
	popl %edx
	popl %ecx
	popl %ebx
	popl %eax
	jmp next_missile


traversal_done:
	leave
	ret


# ---------------------------------ERASE FROM LIST---------------------------------------#

erase_missle:
	# initialize stack frame
	pushl %ebp                 
	movl %esp, %ebp
	# protect callee-saved registers
	pushl %eax
	pushl %ebx
	pushl %ecx
	pushl %esi

	# ebx is the previous pointer, ecx is the current pointer
	# set up ebx:previous cursor
	movl mp1_missile_list, %ebx
	# compare previous cursor with the current cursor
	cmpl %ebx, %ecx
	# jump equal, we are at list head
	je erase_head

next_cursor:
	# otherwise
	# confirm we are at right missle to delete, ebx is the previous pointer
	movl NEXT(%ebx), %esi
	# esi now is the current cursor
	cmpl %esi, %ecx
	je erase
	jmp next_cursor
	
erase: 
	# find next of the previous cursor = current cursor
	movl NEXT(%ecx), %eax
	# call void mp1_free(void *ptr), argument should be pointer
	movl %eax, NEXT(%ebx)
	# free the missile memory
	pushl %ebx
	pushl %eax
	pushl %ecx
	call mp1_free
	popl %ecx
	popl %eax
	popl %ebx

	
	popl %esi
	popl %ecx
	popl %ebx
	popl %eax
	jmp next_missile

erase_head: 
	movl NEXT(%ecx), %edx
	movl %edx, mp1_missile_list
	
	pushl %edx
	pushl %ecx
	call mp1_free
	popl %ecx
	popl %edx

	popl %esi
	popl %ecx
	popl %ebx
	popl %eax
	movl mp1_missile_list, %ecx
	jmp next_missile

# ---------------------------------EXPLOSION---------------------------------------#

# when missle exploded, call missle exploded function
call_exploded: 
	# push edx for argument: "missile *m" 
	pushl %eax
	pushl %ebx
	pushl %ecx
	pushl %edx
	pushl %esi
	pushl %edi
	call missile_explode
	popl %edi
	popl %esi
	popl %edx
	popl %ecx
	popl %ebx
	popl %eax	
	# check the return value of explode function
	cmpl $0, %eax
	je draw_explode
	call mp1_notify_user
	

# tasklet decrement; when it reaches zero the explosion is over
draw_explode: 
	pushl %eax
	pushl %ebx
	pushl %ecx
	pushl %edx
	pushl %esi
	pushl %edi

	# decrement 
	subl $1, EXPLODED(%ecx)
	cmpl $0, EXPLODED (%ecx)
	jle erase_explode
	# edi stores VX
	movl VX(%ecx), %edi 
	# update X
	addl X(%ecx), %edi
	movl %edi, X(%ecx)
	shrl $16, %edi

	# esi stores VY
	movl VY(%ecx), %esi 
	# update Y
	addl Y(%ecx), %esi	
	movl %esi, Y(%ecx)
	shrl $16, %esi
	# memory offset = x*2 + y*80*2
	# calculate x*2
	imull $2, %edi, %edi
	# calculate y*80*2
	imull $80, %esi, %esi
	imull $2, %esi, %esi
	# add  x*2 and y*80*2
	addl %esi, %edi
	# store memory offset in eax
	movl %edi, %eax
	# draw explosion image
	movb EXPLOSION(%ecx), %cl
	movl EXPLODED (%ecx), %edx
	pushl %edx
	call mp1_poke
	popl %edx

	popl %edi
	popl %esi
	popl %edx
	popl %ecx
	popl %ebx
	popl %eax	
	jmp next_missile

next_missile:
	movl NEXT(%ecx),%ecx
	jmp missle_list_traversal

erase_explode:
	# load x value into edi
	movl X(%ecx), %edi
	# shift edi right 16 bit to get x position
	shrl $16, %edi

	# load y value into edi
	movl Y(%ecx), %esi
	# shift edi right 16 bit to get y position
	shrl $16, %esi

	# memory offset = x*2 + y*80*2
	# calculate x*2
	imull $2, %edi, %edi
	# calculate y*80*2
	imull $80, %esi, %esi
	imull $2, %esi, %esi
	# add  x*2 and y*80*2
	addl %esi, %edi
	# store memory offset in eax
	movl %edi, %eax
	movb $32, %cl
	movl EXPLODED (%ecx), %edx
	pushl %edx
	call mp1_poke
	popl %edx
	jmp erase_missle

# -------------------------------Crosshair-----------------------------------#
redraw_the_crosshairs: 
	# initialize stack frame
	pushl %ebp                 
	movl %esp, %ebp
	# protect callee-saved registers
	pushl %esi
	pushl %eax
	# memory offset = x*2 + y*80*2
	# esi stores x
	movl crosshairs_x, %esi
	# eax stores y
	movl crosshairs_y, %eax
	# x*80
	imull $80, %eax
	# x*80 + y
	addl %esi, %eax
	# (x*80 + y) 82
	imull $2, %eax
	# “+” = ascii 43
	movb $43, %cl
	call mp1_poke
	popl %eax
	popl %esi
	leave
	ret

mp1_ioctl_startgame:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi
	movl $0, mp1_missile_list
	popl %edi
    popl %esi
    popl %ebx
    leave
	ret


mp1_ioctl_addmissile:
	# initialize stack frame
	pushl %ebp                 
	movl %esp, %ebp
	# protect callee-saved registers
	pushl %ecx
	pushl %edx
	pushl %esi
	pushl %edi

	movl 8(%ebp), %esi
	# void* mp1 malloc(unsigned long size);
	# struct size = C + size (char) = 32 + 1 = 33
	pushl $33
	call mp1_malloc # eax point to new missle 

	# mp1_copy_from_user (void *to, const void *from, unsigned long n)
	# unsigned long n
	pushl $33
	# const void *from
	pushl %esi
	# void *to = cursor for linked-list
	pushl %eax 
	call mp1_copy_from_user
	# eax point to new missle 
	cmpl $0, %eax 
	# jne copy_failed
	popl %eax
	popl %esi

	# add missile success
	# edx is the start of the old list
	push %eax
	movl mp1_missile_list, %ecx 
	# connect old list with eax
	movl %ecx, NEXT(%eax)
	# insert the new node in the head
	movl %eax, mp1_missile_list
	# no error, return 0
	movl $0, %eax
	popl %eax 

	popl %edi
	popl %esi
	popl %edx
	popl %ecx


	leave 
	ret 
copy_failed:
	# const void *from
	popl %esi
	# void *to = cursor for linked-list
	popl %eax
	push %eax
	call mp1_free
	# copy error, return -1 to eax
	movl $-1, %eax
	
	popl %eax
	popl %edi
	popl %esi
	popl %edx
	popl %ecx

	leave 
	ret 

mp1_ioctl_movexhairs:
		ret

mp1_ioctl_getstatus:
		ret

mp1_ioctl_endgame:
		ret

