#!/bin/make

##########################################
#                                        #
#  Makefile for i.MX HAB encrypted boot  #
#                                        #
##########################################

# required: bc, objcopy (any arch), sed, cst

# Usage:
# 
# Copy u-boot.imx to this directory
#
# $ make dek.bin
#
# Generate dek_blob.bin on the target device by encrypting dek.bin
#
# $ make
#
# Place u-boot-encrypted.imx on the boot medium 
#


# Configuration
RSA_LENGTH?=4096
LOAD_ADDR?=0x87800000
#

MACHINE_BITS != getconf LONG_BIT
CST=../linux$(MACHINE_BITS)/cst

# keyfile dependency - remember to update also u-boot-sign.csf.in when changing filenames
KEYS=../crts/SRK_1_2_3_4_table.bin ../crts/CSF1_1_sha256_$(RSA_LENGTH)_65537_v3_usr_crt.pem ../crts/IMG1_1_sha256_$(RSA_LENGTH)_65537_v3_usr_crt.pem

# u-boot.imx size (hex)
UBOOT_SIZE != echo 0x`stat -c "obase=16; %s" u-boot.imx | bc`

# u-boot.imx size, except IVT
ENCRYPT_SIZE != echo 0x`echo "obase=16;ibase=16; $(UBOOT_SIZE) - 0xC00" | sed -e "s/0x//g" | bc`

# ivt address in DRAM (hex)
IVT_ADDR != echo 0x`echo "obase=16;ibase=16; $(LOAD_ADDR) - 0xC00" | sed -e "s/0x//g" | bc`

# DEK blob address in DRAM 
BLOB_ADDR != echo 0x`echo "obase=16;ibase=16; $(LOAD_ADDR) + $(ENCRYPT_SIZE) + 0x1FB8" | sed -e "s/0x//g" | bc`

.PHONY: all
all: u-boot-encrypted.imx

u-boot-encrypt.csf: u-boot-encrypt.csf.in u-boot.imx
	cat u-boot-encrypt.csf.in | sed \
		-e "s/%%RSA_LENGTH%%/$(RSA_LENGTH)/" \
		-e "s/%%IVT_ADDR%%/$(IVT_ADDR)/" \
		-e "s/%%LOAD_ADDR%%/$(LOAD_ADDR)/" \
		-e "s/%%BLOB_ADDR%%/$(BLOB_ADDR)/" \
		-e "s/%%UBOOT_SIZE%%/$(UBOOT_SIZE)/" \
		-e "s/%%ENCRYPT_SIZE%%/$(ENCRYPT_SIZE)/" \
		> u-boot-encrypt.csf


# this step also encrypts the referenced u-boot binary in place, and generates dek.bin
# copy u-boot.imx to avoid altering an input file
u-boot-hab.bin: u-boot-encrypt.csf u-boot.imx $(KEYS)
	cp u-boot.imx u-boot-copy.imx
	$(CST) -i u-boot-encrypt.csf -o u-boot-hab.bin

dek.bin: u-boot-hab.bin
u-boot-copy.imx: u-boot-hab.bin

u-boot-hab_padded.bin: u-boot-hab.bin
	$(OBJCOPY) objcopy -I binary -O binary --pad-to 0x1FB8 --gap-fill 0xff u-boot-hab.bin u-boot-hab_padded.bin

u-boot-encrypted.imx: u-boot-copy.imx u-boot-hab_padded.bin dek_blob.bin
	cat u-boot-copy.imx  u-boot-hab_padded.bin dek_blob.bin > u-boot-encrypted.imx

.PHONY: clean
clean:
	rm -rf u-boot-encrypt.csf u-boot-copy.imx u-boot-hab.bin u-boot-hab_padded.bin dek.bin u-boot-encrypted.imx

