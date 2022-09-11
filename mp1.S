
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
status:    			.long 0x0

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
		pushl %edx
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		popl %edx
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
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi
		
	pushl %eax    
	call update_missiles
	call update_city
	call redraw_crosshairs


		
tasklet_done:
	popl %eax
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

	movl 8(%esp),%eax
	cmpl $0, %eax
	jb error
	cmpl $4, %eax
	ja error
	jmp *jump_table(,%eax,4)

invalid_cmd:		
	movl $-1, %eax			
	ret

jump_table:
	.long mp1_ioctl_startgame,mp1_ioctl_addmissile,mp1_ioctl_movexhairs,mp1_ioctl_getstatus,mp1_ioctl_endgame



# ----------------------- Functions private to this file -------------------------#

update_missiles:
	# initialize stack frame
	pushl %ebp
	movl %esp, %ebp
	# protect callee-saved registers
	pushl %ebx
	pushl %esi
	pushl %edi
	pushl %edx 
	pushl %ecx
	# place start of missile list into ecx (cursor), and start traversal
	movl mp1_missile_list, %ecx
		
missle_list_traversal:
	cmpl $0, %ecx
	je traversal_done
	pushl %eax               
	pushl %ecx
	# traversal not done, traversal start
	# low 16 bits of x and y fields determine which of these sub-squares the missile is in
	# high 16 bits of x and y determine the text-mode video location to draw the missile

	call missile_position
	# erase current graph on the screen first
	movb $32, %cl				
	call mp1_poke
	popl %ecx
	popl %eax
	
	cmpl $0, EXPLODED(%ecx)
	jne check_bounding

	movl VX(%ecx),%edx
	addl %edx, X(%ecx)
	movl VY(%ecx),%edx
	addl %edx, Y(%ecx)
	
check_bounding: 	
	# load x value into edi
	movl X(%ecx), %edi
	# shift edi right 16 bit to get x position
	shrl $16, %edi  
	# BOUND CHECK: x should be [0,79]
	cmpl $0, %edi
	jl erase_missile
	cmpl $79, %edi
	jg erase_missile

	# load y value into esi
	movl Y(%ecx), %esi
	# shift esi right 16 bit to get y position
	shrl $16, %esi
	# BOUND CHECK: y should be [0,24]
	cmpl $0, %esi
	jl erase_missile
	cmpl $24, %esi
	jg erase_missile


destination_check:
	cmpl $0,EXPLODED(%ecx)						
	jne exploding

	cmpl DEST_X (%ecx), %edi
	jne missle_flying
	cmpl DEST_Y (%ecx), %esi
	jne missle_flying

# ---------------------------------EXPLOSION---------------------------------------#
# when missle exploded, call missle exploded function
exploding:						
	pushl %eax
	pushl %edx
	pushl %ecx
	call missile_explode	 
	# check the return value of explode function
	popl %ecx
	popl %edx
	popl %eax
	cmpl $0,%eax
	je decrement
	# eax return non-zero, we have to notify user
	pushl %eax
	pushl %edx
	pushl %ecx
	call mp1_notify_user
	popl %ecx
	popl %edx
	popl %eax

# tasklet decrement; when it reaches zero the explosion is over
decrement: 
	subl $1, EXPLODED(%ecx)
	cmpl $0, EXPLODED (%ecx)
	jne draw_explode
	call erase_from_list
	# move on to next missile
	movl NEXT(%ecx),%ecx		
	jmp missle_list_traversal     

draw_explode:
	pushl %eax					
	pushl %ecx
	# calculate current missle position and draw image by calling cl and mp1_poke
	call missile_position     
	movb $EXPLOSION,%cl
	call mp1_poke
	popl %ecx
	popl %eax
	# move on to next missile
	movl NEXT(%ecx),%ecx	
	# loop for next missle	
	jmp missle_list_traversal
		

missle_flying:	
	pushl %eax							
	pushl %ecx
	# not explod, it means that missle if flying
	# update the x and y position 
	call missile_position		
	movb C(%ecx), %cl
	call mp1_poke
	popl %ecx
	popl %eax
	# move on to next missile
	movl NEXT(%ecx),%ecx		
	# loop for next missle	
	jmp missle_list_traversal

erase_missile:		
	call erase_from_list

traversal_done:						
	popl %ecx
	popl %edx
	popl %edi
	popl %esi
	popl %ebx
	leave
	ret

missile_position:
	# initialize stack frame
	pushl %ebp
	movl %esp, %ebp
	# draw the new missle image,update the new x, y information back to register
	# update X
	pushl %ebx
	pushl %ecx
	pushl %edx
	pushl %esi
	pushl %edi

	movl 8(%ebp),%ecx 
	# load x value into edi
	movl X(%ecx), %edi
	# shift edi right 16 bit to get x position
	shrl $16, %edi
	# load y value into edi
	movl Y(%ecx), %esi
	# shift edi right 16 bit to get y position
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

	popl %edi
	popl %esi
	popl %edx
	popl %ecx
	popl %ebx

	leave 
	ret

# ---------------------------------ERASE FROM LIST---------------------------------------#
erase_from_list:
	# initialize stack frame
	pushl %ebp                 
	movl %esp, %ebp
	# protect callee-saved registers
	pushl %esi
	pushl %ebx
	pushl %edi
	pushl %edx
	pushl %eax
		
	cmpl $0, %ecx
	je remove_finished
	# load head of the list into ebx				
	movl mp1_missile_list, %ebx			
	# compare with current cursor to see if it is the head
	cmpl %ebx, %ecx
	je remove_head

previous_cursor:	
	# ebx is the previous pointer, ecx is the current pointer
	# set up ebx:previous cursor
	movl NEXT(%ebx), %eax
	# compare previous cursor with the current cursor
	cmpl %eax, %ecx		
	# next cursor = current cursor, we remove the body of the list				
	je remove_body
	# otherwise find the next missile until reach the node
	movl NEXT(%ebx),%ebx				
	jmp previous_cursor

remove_head: 	
	movl NEXT(%ecx), %eax
	movl %eax, mp1_missile_list	
	# call void mp1_free(void *ptr), argument should be pointer		
	pushl %eax
	pushl %ebx
	pushl %ecx
	# free the missile memory
	call mp1_free								
	popl %ecx				   			
	popl %ebx
	popl %eax
	# let ecx point to the head of the new list
	movl mp1_missile_list, %ecx	    	
	jmp remove_finished

remove_body:	
	# find next of the current cursor, connect with the previous cursor, free the middle part	
	movl NEXT(%ecx), %eax
	movl %eax, NEXT(%ebx)
	# call void mp1_free(void *ptr), argument should be pointer					
	pushl %ebx
	pushl %eax
	pushl %ecx		
	# free the missile memory
	call mp1_free
	popl %ecx						
	popl %eax
	popl %ebx
	# connect with the previous cursor
	movl %ebx, %ecx    				
	jmp remove_finished
remove_finished:	
	popl %eax
	popl %edx 
	popl %edi
	popl %ebx
	popl %esi
	leave
	ret
# ---------------------------------CROSSHAIR DRAWING---------------------------------------#

redraw_crosshairs:
	# initialize stack frame
	pushl %ebp                 
	movl %esp, %ebp
	# protect callee-saved registers
	pushl %ebx
	pushl %ecx
	pushl %edx
	pushl %esi
	pushl %edi
	# memory offset = x*2 + y*80*2
	# esi stores x
	xorl %esi,%esi
	movl crosshairs_x, %esi
	# eax stores y
	movl crosshairs_y, %eax
	# y*80
	imull $80, %eax
	# x*80 + y
	addl %esi, %eax
	# (x*80 + y) *2
	imull $2, %eax
	# “+” = ascii 43
	movb $43, %cl

	pushl %edx
	call mp1_poke
	popl %edx

	popl %edi
	popl %esi
	popl %edx
	popl %ecx
	popl %ebx
	leave
	ret



# ---------------------------------BASE DRAWING---------------------------------------#
# three cities should be drawn in the bottom row of the screen centered in columns 20, 40, and 60
# two five-character arrays declared in mp1.S: base_pic and dead_base pic
# first city: five video locations from (18,24) to (22, 24)
# base alive array: indicates whether each city has been destroyed
# base_alive [0] - base_alive [2] : zero -> dead 
# 									non-zero ->  alive
# The fourth byte is padding.
update_city:
	# initialize stack frame
	pushl %ebp
    movl %esp, %ebp
	# protect callee-saved registers
	pushl %ebx
	pushl %ecx
	pushl %edx
	pushl %esi
	pushl %edi	
	# let ecx point to the start of the base_alive
	movl base_alive, %ecx                                  

check_1st_city: 
	# each base has width of 5, use ecx decrement for checking
    movl $5, %ebx      
	# Base on has location [18,24], move edx to the leftmost point                                     
    movl $18, %edx  
	# clear esi and store alive base image "base_pic"                                         
	leal base_pic, %esi     
	# compare 0 and base_alive                              
	cmpb $0, %cl 
	jne draw_1st_city
	# base_alive == 0 meanse city is dead, then load the dead image
	# load the dead image              
    leal dead_base_pic, %edi 
	movl %edi, %esi

draw_1st_city: 
	# memory offset = x*2 + y*80*2
	# in this case, memory location is 18*2+24*80*2
    xorl %eax, %eax                                                 
    movl %edx, %eax 
	imull $2, %eax   
	# draw the image by calling cl and mp1 poke    
	# 3840 = 24*80*2                            
    addl $3840, %eax  
	movb (%esi), %cl                                      
    pushl %edx
    call mp1_poke											
    popl %edx
	# decrement width by 1
	subl $1, %ebx
	# increament memory location by 1
    addl $1, %edx  
	# increament base_pic by 1                                  
    addl $1, %esi    
	# stop drawing until 5                                           
    cmpl $0, %ebx
    jne draw_1st_city
    
check_2nd_city:     
	# each base has width of 5, use ecx decrement for checking
    movl $5, %ebx
	# Base on has location [38,24], move edx to the leftmost point
    movl $38, %edx
	# clear esi and store alive base image "base_pic"                                         
    leal base_pic, %esi 
	# find next "base_alive" by shift 1 byte
	shrl $8, %ecx 
	# compare 0 and base_alive                                                                                                      
	cmpb $0, %cl
	jne draw_2nd_city
	# base_alive == 0 meanse city is dead, then load the dead image
	# load the dead image 
	xorl %esi, %esi
    leal dead_base_pic, %edi   
	movl %edi, %esi

draw_2nd_city: 
	# memory offset = x*2 + y*80*2
	# in this case, memory location is 38*2+24*80*2
    xorl %eax, %eax                                                 
    movl %edx, %eax 
	imull $2, %eax 
	# draw the image by calling cl and mp1 poke    
	# 3840 = 24*80*2                                                                  
    addl $3840, %eax  
	movb (%esi), %cl                                      
    pushl %edx
    call mp1_poke											
    popl %edx
	# decrement width by 1
	subl $1, %ebx
	# increament memory location by 1
    addl $1, %edx  
	# increament base_pic by 1                                  
    addl $1, %esi    
	# stop drawing until 5                                           
    cmpl $0, %ebx
    jne draw_2nd_city
    
check_3rd_city:    
	# each base has width of 5, use ecx decrement for checking
    movl $5, %ebx
	# Base on has location [58,24], move edx to the leftmost point
    movl $58, %edx
	# clear esi and store alive base image "base_pic"                                         
    leal base_pic, %esi 
	# find next "base_alive" by shift 1 byte
    shrl $8, %ecx      
	# compare 0 and base_alive                                                                                                                                         
    cmpb $0, %cl
	jne draw_3rd_city
	# base_alive == 0 meanse city is dead, then load the dead image
	# load the dead image 
    leal dead_base_pic, %edi   
	movl %edi, %esi

draw_3rd_city: 
	# memory offset = x*2 + y*80*2
	# in this case, memory location is 58*2+24*80*2
    xorl %eax, %eax                                                 
    movl %edx, %eax 
	imull $2, %eax    
	# draw the image by calling cl and mp1 poke   
	# 3840 = 24*80*2                                                                                                    
    addl $3840, %eax  
	movb (%esi), %cl                                      
    pushl %edx
    call mp1_poke											
    popl %edx
	# decrement width by 1
	subl $1, %ebx
	# increament memory location by 1
    addl $1, %edx  
	# increament base_pic by 1                                  
    addl $1, %esi    
	# stop drawing until 5                                           
    cmpl $0, %ebx
    jne draw_3rd_city
    
	popl %edi
	popl %esi
	popl %edx
	popl %ecx
	popl %ebx
    leave
    ret

mp1_ioctl_startgame:

	movl $0, mp1_missile_list
	movl $40, crosshairs_x		
	movl $12, crosshairs_y 
	movl $0xFFFFFFFF, base_alive
	leave
	ret
	


mp1_ioctl_addmissile:
	# initialize stack frame
	pushl %ebp
	movl %esp, %ebp
	# protect callee-saved registers
	pushl %esi
	pushl %ebx
	pushl %edi
	pushl %ecx
	pushl %edx
	# let ecx point to the struct
	movl 8(%ebp),%ebx	

	# protect callee-saved registers
	pushl %ebx	
	# void* mp1 malloc(unsigned long size);
	# struct size = C + size (char) = 32 + 1 = 33			
	pushl $33 
	call mp1_malloc  
	# eax point to new missle  		
	addl $4, %esp
	popl %ebx

	# mp1_copy_from_user (void *to, const void *from, unsigned long n)
	# unsigned long n
	pushl $33 		
	# const void *from	
	pushl %ebx
	# void *to = cursor for new linked-list
	pushl %eax
	call mp1_copy_from_user	
	# eax point to new missle 		
	cmpl $0,%eax			
	jne copy_failed
	popl %eax							
	popl %ebx					

	# add missile success
	# edx is the start of the old list	
	movl mp1_missile_list, %edx 
	# connect old list with eax
	movl %edx,NEXT(%eax)	
	# insert the new node in the head
	movl %eax,mp1_missile_list
	# no error, return 0
	movl $0,%eax				  
	
	popl %edx	
	popl %ecx 
	popl %edi 
	popl %ebx
	popl %esi
	leave
	ret

copy_failed:
	# void *to = cursor for new linked-list
	popl %eax	
	# const void *from							
	popl %ebx

	# void *to = cursor for new linked-list
	pushl %eax
	call mp1_free
	addl $4,%esp	
	# copy error, return -1 to eax			
	movl $-1,%eax				
	
	popl %edx	
	popl %ecx 
	popl %edi 
	popl %ebx
	popl %esi
	leave
	ret

		
				
mp1_ioctl_movexhairs:
		
# The low 16 bits contain x component of the crosshair position 
# the high 16 bits contain the y component 
	
	# initialize stack frame
	pushl %ebp                 
	movl %esp, %ebp
	# protect callee-saved registers
	pushl %ebx
	pushl %ecx
	pushl %edx
	pushl %esi
	pushl %edi

	# first: find current crosshair and erase
	# let edx point to the argument on stack
	movl 8(%ebp), %edx	
	# edx = x argument
	shll $16, %edx				
	sarl $16, %edx

	# edi = y argument
	movl 8(%ebp), %edi			
	sarl $16, %edi	

	# esi = x *2
	movl crosshairs_x, %esi
	imull $2, %esi
	# edi = y*80*2
	movl crosshairs_y, %ecx
	imull $160, %ecx
	# x+y
	addl %esi, %ecx
	# eax = x*2 + y*80*2
	movl %ecx, %eax
	# erase the crosshair
	movb $32, %cl

	call mp1_poke

	# edx = updated x-value
	addl crosshairs_x, %edx
	# edi = updated y-value
	addl crosshairs_y, %edi

crosshair_bound_check: 
	# edi = updated y-value
	# y should be [0,24]
	cmpl $0, %edi
	jl below_y
	cmpl $24, %edi
	jg above_y
	movl %edi, crosshairs_y
	# edx = updated x-value
	# x should be [0,79]
	cmpl $0, %edx	
	jl below_x
	cmpl $79, %edx		
	jg above_x
	movl %edx, crosshairs_x
	jmp check_done
	# x below 0, replace it with 0

below_y: 
	movl $0, crosshairs_y
	jmp crosshair_bound_check
	# y above 24, replace it with 24
above_y: 
	movl $24, crosshairs_y
	jmp crosshair_bound_check
below_x: 			
	movl $0, crosshairs_x	
	jmp crosshair_bound_check
	# x above 79, replace it with 79
above_x: 
	movl $79, crosshairs_x

	# bound check over, return 0
	movl $0, %eax

check_done: 
	# esi = x *2
	movl crosshairs_x, %esi
	imull $2, %esi
	# edi = y*80*2
	movl crosshairs_y, %ecx
	imull $160, %ecx
	# x+y
	addl %esi, %ecx
	# eax = x*2 + y*80*2
	movl %ecx, %eax
	# erase the crosshair
	movb $43, %cl

	call mp1_poke
    
	popl %edi
	popl %esi
	popl %edx
	popl %ecx
	popl %ebx

	leave
	ret


mp1_ioctl_getstatus:

	pushl %ebp
	movl %esp, %ebp
	pushl %esi
	pushl %ebx
	pushl %edi
	pushl %edx 
	pushl %ecx

	# city is currently alive, the corresponding bit should be a 1
	# city has been destroyed, the bit should be 0	
	# initialize ecx to store city status
	xorl %ecx, %ecx	
	
check_1st_city_status: 
	# load the base_alive array into eax
	movl base_alive, %eax
	# check if the first city is alive
	movl $0x000000ff, %ebx	
	andl %ebx, %eax		
	cmpl $0, %eax
	# city alive, corresponding bit should be 1
	# otherwise, jump for next city
	je check_2nd_city_status
	# add 1 to the first bit of ecx
	addl $1, %ecx
	
check_2nd_city_status:
	# load the base_alive array into eax
	movl base_alive, %eax	
	# check if the first city is alive		
	movl $0x0000ff00, %ebx
	andl %ebx, %eax		
	cmpl $0, %eax
	# city alive, corresponding bit should be 1
	# otherwise, jump for next city
	je check_3rd_city_status
	# add 1 to the second bit of ecx		
	addl $2, %ecx			

check_3rd_city_status:
	# load the base_alive array into eax
	movl base_alive, %eax
	# check if the first city is alive
	movl $0x00ff0000, %ebx	
	andl %ebx, %eax
	cmpl $0, %eax
	# city alive, corresponding bit should be 1
	# otherwise, jump for next city
	je update_score
	# add 1 to the third bit of ecx
	addl $4, %ecx		

update_score:
	# shift left by 16, so the 3 bit  will be on 16th, 17th, 18th place
	shll $16, %ecx
	# insert mp1_score to the lower 16 bit 
	movw mp1_score, %cx
	movl %ecx, score
	# unsigned long mp1 copy to user (void *to, const void *from, unsigned long n);
	# "unsigned long n"
	pushl $4	
	# "const void *from	""				
	pushl $score
	# "void *to"
	pushl 8(%ebp)
	call mp1_copy_to_user
	addl $12,%esp  	
	# check the return value of mp1_copy_to_user				
	cmpl $0,%eax
	# sucess then jump to done
	je getstatus_done
	# copy failed, return -1
	movl $-1,%eax

getstatus_done:
	popl %ecx
	popl %edx 
	popl %edi 
	popl %ebx
	popl %esi
	leave 
	ret 

	
mp1_ioctl_endgame:
# initialize stack frame
	pushl %ebp                 
	movl %esp, %ebp
	# protect callee-saved registers
	pushl %ebx
	pushl %ecx
	pushl %edx
	pushl %esi
	pushl %edi
	movl mp1_missile_list, %edi
list_clean: 
	# check the head of the missle list
	movl mp1_missile_list, %edi
	cmpl $0, %edi
	je gameover

	movl NEXT(%edi), %esi
	movl %esi, mp1_missile_list
	pushl %esi
	pushl %edi
	call mp1_free
	popl %edi
	popl %esi
	
	jmp list_clean
gameover: 
	popl %edi
	popl %esi
	popl %edx
	popl %ecx
	popl %ebx
	movl $0, %eax
	leave
	ret
