# ECG-CNN-FPGA
FPGA-based RTL implementation of a 1D CNN accelerator for ECG arrhythmia detection using parameterized Conv1D engines, fixed-point quantization, and DSP-efficient MAC reuse architecture.

 ECG Arrhythmia Detection CNN Accelerator on FPGA

>> Overview
This project implements a hardware accelerator for ECG arrhythmia detection using a 1D Convolutional Neural Network (CNN) designed entirely in RTL for FPGA deployment. The objective is to enable low-latency and resource-efficient neural network inference suitable for edge medical devices.

>> Motivation
Software-based CNN inference introduces high latency and power consumption for real-time biomedical signal processing. This project explores FPGA-based acceleration by translating CNN computation into optimized hardware datapaths.

>> Architecture
 The accelerator consists of:
> Parameterized Conv1D RTL Engine
> MAC reuse architecture for DSP optimization
> Fixed-point quantized inference
> Pooling layer implementation
> Prediction (Argmax) module
> FSM-based control unit for layer scheduling
> The design supports scalable input channels and kernel configurations.

>> Key Hardware Features
> Fully synthesizable SystemVerilog RTL
> DSP-efficient multiply-accumulate reuse
> Pipelined datapath design
> Parallel channel computation
> Memory-aware convolution scheduling
> FPGA-friendly fixed-point arithmetic

>> Verification
> Functional verification using SystemVerilog testbenches
> Waveform validation using simulation tools
> Layer-wise output validation against software model

>> Tools & Technologies
> SystemVerilog / Verilog
> Vivado 
> GTKWave

>> Applications
> Real-time ECG monitoring
> Edge AI healthcare devices
> Low-power biomedical signal processing
> FPGA-based neural network acceleration
