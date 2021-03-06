/*
 * Copyright 2017, Data61
 * Commonwealth Scientific and Industrial Research Organisation (CSIRO)
 * ABN 41 687 119 230.
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(DATA61_GPL)
 */

#include <config.h>
#include <machine/assembler.h>
#include <arch/machine/hardware.h>
#include <arch/machine/registerset.h>
#include <util.h>

#ifndef ALLOW_UNALIGNED_ACCESS
#define ALLOW_UNALIGNED_ACCESS 1
#endif

#if ALLOW_UNALIGNED_ACCESS
#define CR_ALIGN_SET     0
#define CR_ALIGN_CLEAR   BIT(CONTROL_A)
#else
#define CR_ALIGN_SET     BIT(CONTROL_A)
#define CR_ALIGN_CLEAR   0
#endif

#ifndef CONFIG_DEBUG_DISABLE_L1_ICACHE
    #define CR_L1_ICACHE_SET   BIT(CONTROL_I)
    #define CR_L1_ICACHE_CLEAR 0
#else
    #define CR_L1_ICACHE_SET   0
    #define CR_L1_ICACHE_CLEAR BIT(CONTROL_I)
#endif

#ifndef CONFIG_DEBUG_DISABLE_L1_DCACHE
    #define CR_L1_DCACHE_SET   BIT(CONTROL_C)
    #define CR_L1_DCACHE_CLEAR 0
#else
    #define CR_L1_DCACHE_SET   0
    #define CR_L1_DCACHE_CLEAR BIT(CONTROL_C)
#endif

#define CR_BITS_SET    (CR_ALIGN_SET | \
                        CR_L1_ICACHE_SET | \
                        CR_L1_DCACHE_SET | \
                        BIT(CONTROL_M))

#define CR_BITS_CLEAR  (CR_ALIGN_CLEAR | \
                        CR_L1_ICACHE_CLEAR | \
                        CR_L1_DCACHE_CLEAR | \
                        BIT(CONTROL_SA0) | \
                        BIT(CONTROL_EE) | \
                        BIT(CONTROL_E0E))

/*
 * Entry point of the kernel ELF image.
 * X0-X3 contain parameters that are passed to init_kernel().
 *
 * Note that for SMP kernel, the tpidr_el1 is used to pass
 * the logical core ID.
 */

#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT
#define SCTLR   sctlr_el2
#else
#define SCTLR   sctlr_el1
#endif

.section .boot.text
BEGIN_FUNC(_start)
    /* Make sure interrupts are disable */
    msr daifset, #DAIFSET_MASK

    /* Initialise sctlr_el1 or sctlr_el2 register */
    msr     spsel, #1
    mrs     x4, SCTLR
    ldr     x19, =CR_BITS_SET
    ldr     x20, =CR_BITS_CLEAR
    orr     x4, x4, x19
    bic     x4, x4, x20
    msr     SCTLR, x4

#ifdef ENABLE_SMP_SUPPORT
    /* tpidr_el1 has the logic ID of the core, starting from 0 */
    mrs     x6, tpidr_el1
    /* Set the sp for each core assuming linear indices */
    ldr     x5, =BIT(CONFIG_KERNEL_STACK_BITS)
    mul     x5, x5, x6
    ldr     x4, =kernel_stack_alloc + BIT(CONFIG_KERNEL_STACK_BITS)
    add     x4, x4, x5
    mov     sp, x4
    /* the kernel stack must be 4-KiB aligned since we use the
       lowest 12 bits to store the logical core ID. */
    orr     x6, x6, x4
#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT
    msr     tpidr_el2, x6
#else
    msr     tpidr_el1, x6
#endif
#else
    ldr    x4, =kernel_stack_alloc + BIT(CONFIG_KERNEL_STACK_BITS)
    mov    sp, x4
#endif /* ENABLE_SMP_SUPPORT */

    /* Attempt to workaround any known ARM errata. */
    stp     x0, x1, [sp, #-16]!
    stp     x2, x3, [sp, #-16]!
    bl arm_errata
    ldp     x2, x3, [sp], #16
    ldp     x0, x1, [sp], #16

    /* Call bootstrapping implemented in C */
    bl      init_kernel

    /* Restore the initial thread */
    b restore_user_context
END_FUNC(_start)
