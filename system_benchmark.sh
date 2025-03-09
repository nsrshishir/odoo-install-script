#!/bin/bash

# Function to check if Sysbench is installed and install it if necessary
check_and_install_sysbench() {
    if ! command -v sysbench &> /dev/null; then
        echo "Sysbench is not installed. Installing Sysbench..."
        sudo apt-get update
        sudo apt-get install -y sysbench
    else
        echo "Sysbench is already installed."
    fi
}

# Function to run CPU benchmark
run_cpu_benchmark() {
    echo "Running CPU Benchmark..."
    sudo sysbench cpu --cpu-max-prime=20000 run > cpu_benchmark.txt
    cpu_result=$(grep "total time:" cpu_benchmark.txt | awk '{print $NF}')
    cpu_events_per_second=$(grep "events per second:" cpu_benchmark.txt | awk '{print $NF}')
    echo "CPU Benchmark Summary:"
    echo "  Total Time: $cpu_result seconds"
    echo "  Events per Second: $cpu_events_per_second"
}

# Function to run Memory benchmark
run_memory_benchmark() {
    echo "Running Memory Benchmark..."
    sudo sysbench memory --memory-block-size=1K --memory-total-size=100G run > memory_benchmark.txt
    memory_operations=$(grep "Operations performed:" memory_benchmark.txt | awk '{print $NF}')
    memory_transfer_rate=$(grep "transferred" memory_benchmark.txt | awk '{print $1, $2}')
    echo "Memory Benchmark Summary:"
    echo "  Total Operations: $memory_operations"
    echo "  Transfer Rate: $memory_transfer_rate"
}

# Function to run Disk I/O benchmark
run_disk_io_benchmark() {
    echo "Running Disk I/O Benchmark..."
    sudo sysbench fileio --file-total-size=1G prepare
    sudo sysbench fileio --file-total-size=1G --file-test-mode=rndrw --time=300 run > disk_io_benchmark.txt
    read_mib=$(grep "Read MiB/s" disk_io_benchmark.txt | awk '{print $NF}')
    write_mib=$(grep "Written MiB/s" disk_io_benchmark.txt | awk '{print $NF}')
    echo "Disk I/O Benchmark Summary:"
    echo "  Read Throughput: $read_mib MiB/s"
    echo "  Write Throughput: $write_mib MiB/s"
    sudo sysbench fileio --file-total-size=1G cleanup
}

# Main function to execute all benchmarks
main() {
    echo "Starting System Benchmark..."
    check_and_install_sysbench
    run_cpu_benchmark
    run_memory_benchmark
    run_disk_io_benchmark
    echo "System Benchmark Completed."
}

# Execute the main function
main
