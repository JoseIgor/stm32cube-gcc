# STM32 Makefile for GNU toolchain and openocd
#
# This Makefile fetches the Cube firmware package from ST's' website.
# This includes: CMSIS, STM32 HAL, BSPs, USB drivers and examples.
#
# Usage:
#	make cube		Download and unzip Cube firmware
#	make program		Flash the board with OpenOCD
#	make openocd		Start OpenOCD
#	make debug		Start GDB and attach to OpenOCD
#	make dirs		Create subdirs like obj, dep, ..
#	make template		Prepare a simple example project in this dir
#
# Copyright	2015 Steffen Vogel
# License	http://www.gnu.org/licenses/gpl.txt GNU Public License
# Author	Steffen Vogel <post@steffenvogel.de>
# Link		http://www.steffenvogel.de


# A name common to all output files (elf, map, hex, bin, lst)
TARGET     = demo

# Take a look into $(CUBE_DIR)/Drivers/BSP for available BSPs . BSP = Board Supported Package.


# Define the microcontroller that you'll use.
# See cube/Drivers/CMSIS/Device/ST/STM32F4xx/Include/stm32f4xx.h
# in section "Device_Included" to get the correct DEF_MCU name.
DEF_MCU = STM32F401xE


OCDFLAGS   = -f board/st_nucleo_f4.cfg
GDBFLAGS   =


# MCU family and type in various capitalizations o_O

#EXAMPLE   = Templates
EXAMPLE    = Examples/GPIO/GPIO_IOToggle
# path of the ld-file inside the example directories
LDFILE     = $(EXAMPLE)/SW4STM32/STM32F4xx-Nucleo/STM32F401VEHx_FLASH.ld

# Your C files from the /src directory
SRCS       = main.c
SRCS      += system_stm32f4xx.c
SRCS      += stm32f4xx_it.c

# Basic HAL libraries
SRCS      += stm32f4xx_hal_rcc.c stm32f4xx_hal_rcc_ex.c 
SRCS      += stm32f4xx_hal.c stm32f4xx_hal_cortex.c 
SRCS      += stm32f4xx_hal_gpio.c stm32f4xx_hal_pwr_ex.c stm32f4xx_nucleo.c

# Directories
OCD_DIR    = /usr/share/openocd/scripts

CUBE_DIR   = cube

BSP_DIR    = $(CUBE_DIR)/Drivers/BSP/STM32F4xx-Nucleo
HAL_DIR    = $(CUBE_DIR)/Drivers/STM32F4xx_HAL_Driver
CMSIS_DIR  = $(CUBE_DIR)/Drivers/CMSIS
DEV_DIR    = $(CMSIS_DIR)/Device/ST/STM32F4xx

#Download stm32cubef4 from internet
CUBE_URL   = http://www.st.com/st-web-ui/static/active/en/st_prod_software_internet/resource/technical/software/firmware/stm32cubef4.zip

# that's it, no need to change anything below this line!

###############################################################################
# Toolchain

PREFIX     = arm-none-eabi
CC         = $(PREFIX)-gcc
AR         = $(PREFIX)-ar
OBJCOPY    = $(PREFIX)-objcopy
OBJDUMP    = $(PREFIX)-objdump
SIZE       = $(PREFIX)-size
GDB        = $(PREFIX)-gdb

OCD        = openocd

###############################################################################
# Options

# Defines
#Define the correct MCU to be used and enable the use of HAL libraries
DEFS       = -D$(DEF_MCU) -DUSE_HAL_DRIVER

# Debug specific definitions for semihosting
DEFS       += -DUSE_DBPRINTF

# Include search paths (-I)
INCS       = -Iapp/inc
INCS      += -I$(BSP_DIR)
INCS      += -I$(CMSIS_DIR)/Include
INCS      += -I$(DEV_DIR)/Include
INCS      += -I$(HAL_DIR)/Inc

# Library search paths
LIBS       = -L$(CMSIS_DIR)/Lib

# Compiler flags
CFLAGS     = -Wall -g -std=c99 -Os
CFLAGS    += -mlittle-endian -mcpu=cortex-m4 -march=armv7e-m -mthumb
CFLAGS    += -mfpu=fpv4-sp-d16 -mfloat-abi=hard
CFLAGS    += -ffunction-sections -fdata-sections
CFLAGS    += $(INCS) $(DEFS)

# Linker flags
LDFLAGS    = -Wl,--gc-sections -Wl,-Map=build/bin/$(TARGET).map $(LIBS) -Tapp/stm32f401xx.ld

# Enable Semihosting
LDFLAGS   += --specs=rdimon.specs -lc -lrdimon

# Source search paths
VPATH      = ./app/src
VPATH     += $(BSP_DIR)
VPATH     += $(HAL_DIR)/Src
VPATH     += $(DEV_DIR)/Source/

OBJS       = $(addprefix build/obj/,$(SRCS:.c=.o))
DEPS       = $(addprefix build/dep/,$(SRCS:.c=.d))

# Prettify output
V = 0
ifeq ($V, 0)
	Q = @
	P = > /dev/null
endif

###################################################

.PHONY: all dirs program debug template clean

all: build/bin/$(TARGET).bin

-include $(DEPS)

dirs: build/dep build/obj build/bin docs test app/src app/inc cube
build/dep build/obj build/bin docs test app/src app/inc:
	@echo "[MKDIR]  $@"
	$Qmkdir -p $@

build/obj/%.o : %.c | dirs
	@echo "[CC]      $(notdir $<)"
	$Q$(CC) $(CFLAGS) -c -o $@ $< -MMD -MF build/dep/$(*F).d

build/bin/$(TARGET).elf: $(OBJS)
	@echo "[LD]      build/bin/$(TARGET).elf"
	$Q$(CC) $(CFLAGS) $(LDFLAGS) app/src/startup_stm32f401xe.s $^ -o $@
	@echo "[OBJDUMP] build/bin/$(TARGET).lst"
	$Q$(OBJDUMP) -St build/bin/$(TARGET).elf >build/bin/$(TARGET).lst
	@echo "[SIZE]    build/bin/$(TARGET).elf"
	$(SIZE) build/bin/$(TARGET).elf


build/bin/$(TARGET).bin: build/bin/$(TARGET).elf
	@echo "[OBJCOPY] build/bin/$(TARGET).bin"
	$Q$(OBJCOPY) -O binary $< $@


openocd:
	$(OCD) -s $(OCD_DIR) $(OCDFLAGS)

program: all
	$(OCD) -s $(OCD_DIR) $(OCDFLAGS) -c "program build/bin/$(TARGET).elf verify reset"

debug:
	@if ! nc -z localhost 3333; then \
		echo "\n\t[Error] OpenOCD is not running! Start it with: 'make openocd'\n"; exit 1; \
	else \
		$(GDB)  -ex "target extended localhost:3333" \
			-ex "monitor arm semihosting enable" \
			-ex "monitor reset halt" \
			-ex "load" \
			-ex "monitor reset init" \
			$(GDBFLAGS) $(TARGET).elf; \
	fi

cube:
	rm -fr $(CUBE_DIR)
	wget --tries=45 -O $$PWD/cube.zip $(CUBE_URL) 
	unzip $$PWD/cube.zip
	mv STM32Cube* $(CUBE_DIR)
	chmod -R u+w $(CUBE_DIR)
	rm -f $$PWD/cube.zip


template: cube app/src app/inc
	cp -ri $(CUBE_DIR)/Projects/STM32F401RE-Nucleo/$(EXAMPLE)/Src/* app/src
	cp -ri $(CUBE_DIR)/Projects/STM32F401RE-Nucleo/$(EXAMPLE)/Inc/* app/inc
	cp -i $(DEV_DIR)/Source/Templates/gcc/startup_stm32f401xe.s app/src
	cp -i $(CUBE_DIR)/Projects/STM32F401RE-Nucleo/$(LDFILE) app/stm32f401xx.ld

clean:
	@echo "[RM]      build/bin/$(TARGET).bin"; rm -f build/bin/$(TARGET).bin
	@echo "[RM]      build/bin/$(TARGET).elf"; rm -f build/bin/$(TARGET).elf
	@echo "[RM]      build/bin/$(TARGET).map"; rm -f build/bin/$(TARGET).map
	@echo "[RM]      build/bin/$(TARGET).lst"; rm -f build/bin/$(TARGET).lst
	@echo "[RMDIR]   build/dep"              ; rm -fr build/dep/*
	@echo "[RMDIR]   build/obj"              ; rm -fr build/obj/*

