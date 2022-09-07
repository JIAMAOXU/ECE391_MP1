
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
	pushl %ebx
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

	popl %edi
    popl %esi
    popl %ebx
    
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
		ret


# ----------------- Functions private to this file -------------------


update_missiles:
	# initialize stack frame
	pushl %ebp                 
	movl %esp, %ebp
	# protect callee-saved registers
	pushl %ebx
	pushl %esi
	pushl %edi
	# place start of missile list into ecx (cursor), and start traversal
	movl mp1_missile_list, %ecx
	# compare ebx with 0 to see if finish the traversal
	cmpl $0, %ecx
	je traversal_done

missle_list_traversal:
	# traversal not done, traversal start
	# low 16 bits of x and y fields determine which of these sub-squares the missile is in
	# high 16 bits of x and y determine the text-mode video location to draw the missile
	movl 8(%ebp),%ecx

	# load x value into edi
	movl X(%ecx), %edi
	# shift edi right 16 bit to get x position
	shrl $16, %edi

	# BOUND CHECK: x should be [0,24]
	compl $0, %edi
	jl erase_missle
	compl $24, %edi
	jg erase_missle

	# load y value into edi
	movl Y(%ecx), %esi
	# shift edi right 16 bit to get y position
	shrl $16, %esi

	# BOUND CHECK: y should be [0,80]
	comp $0, %esi
	jl erase_missle
	compl $79, %esi
	jg erase_missle

	# EXPLOSION CHECK: check if missle is exploded
	cmpl $0, EXPLODED(%ecx)
	jne missle_exploded
	
	# DESTINATION CHECK: check if missle reach destination
	cmpl DEST_X (%ecx), %edi
	jne missle_flying
	cmpl DEST_Y (%ecx), %esi
	jne missle_flying

	# missle x and y position same as destination, jump to missle exploded
	jmp missle_exploded
	
	
missle_flying: 
	# if not exploded, it means that missle if flying
	# update the x and y position based on vx and vy

	# first remove the old missle image

	call erase_missle

	# draw the new missle image,update the new x, y information back to register
	# update X
	movl VX(%ecx), %edi # edi stores VX
	addl %edi, X(%ecx)	# update X
	shrl $16, %edi
	# update Y
	movl VY(%ecx), %esi # esi stores VY
	addl %esi, Y(%ecx)	# update Y
	shrl $16, %esi

	# Start drawing procedure
<<<<<<< Updated upstream
=======
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
	movl 0x00, 
	call mp1_poke
>>>>>>> Stashed changes



traversal_done:
leave
ret


erase_missle:
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

	# ebx is the previous pointer, ecx is the current pointer
	# set up ebx:previous cursor
	movl mp1_missile_list, %ebx
	# compare previous cursor with the current cursor
	compl %ebx, %ecx
	# if equal means we are at list head
	je erase_missle_head

next_cursor:
	# otherwise
	# confirm we are at right missle to delete, ebx is the previous pointer
	movl NEXT(%ebx), %edx
	# edx now is the current cursor
	comp %edx, %ecx
	je erase
	jmp next_cursor
erase: 
	# find next of the previous cursor = current cursor
	movl NEXT(%ebx), %eax
	# call void mp1_free(void *ptr), argument should be pointer
	movl %eax, NEXT(%edx)
	call mp1_free
	leave
	ret
erase_head: 
	movl NEXT(%ecx), %edx
	movl %edx, mp1_missile_list
	pushl %edx
	pushl %ecx
	call mp1_free
	popl %ecx
	popl %edx
	movl mp1_missile_list, %ecx
	leave
	ret




# when missle exploded, call missle exploded function
call_exploded: 
	# push edx for argument: "missile *m" 
	pushl %edx
	call missle_exploded
	popl %edx

	# check the return value of explode function
	compl $0, %eax
	je explode_finish
	jmp explosion_side_effect

# tasklet decrement; when it reaches zero the explosion is over
explode_finish: 
# decrement 
subl $1, EXPLODED(%ecx)
cmpl $0, EXPLODED (%ecx)
je erase_explosion

erase_explosion:


# Has to notify user if missle_explode changes game status
explosion_side_effect: 
# How many argument??
	pushl xxxxx
	pushl xxxxx
	call mp1_notify_user
	popl  xxxxx
	popl  xxxxx
	jmp explode_finish

mp1_ioctl_startgame:
		ret

mp1_ioctl_addmissile:
		ret

mp1_ioctl_movexhairs:
		ret

mp1_ioctl_getstatus:
		ret

mp1_ioctl_endgame:
		ret


# TA questions
# 1. mp1_poke has what function?
# 2. check bound before update or after update? 
# 3. How to draw explosion