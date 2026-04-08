FPGA CNN Accelerator for ECG Arrhythmia Classification
Overview
This project implements a 1D Convolutional Neural Network (CNN) accelerator in SystemVerilog for ECG arrhythmia classification.
The design processes ECG signals through multiple convolution layers followed by global average pooling and a fully connected prediction layer. The implementation is targeted for FPGA and demonstrates hardware acceleration of CNN inference.
CNN Pipeline
The accelerator implements the following stages:
1.	1D Convolution layers
2.	ReLU activation
3.	Feature map buffering
4.	Global Average Pooling (GAP)
5.	Final classification layer
Project Structure
The repository contains two main folders:
synthesis/
Contains synthesizable RTL intended for FPGA implementation.
In this version, ECG input samples are stored in ROM.
simulation/
Contains simulation environment and testbench.
This version replaces the ROM with a RAM interface to allow dynamic loading of ECG samples during simulation.
The convolution compute engine is identical in both versions.
Design Language
SystemVerilog (hand-coded RTL)
Application Domain
Healthcare signal processing – ECG arrhythmia classification using FPGA acceleration.
