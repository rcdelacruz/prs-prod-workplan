#!/bin/bash

# PRS Documentation Server Script
# Serves MkDocs documentation locally for development and viewing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install MkDocs
install_mkdocs() {
    print_status "Installing MkDocs and dependencies..."

    # Check if Python3 is installed
    if ! command_exists python3; then
        print_error "Python3 is not installed. Please install Python3 first."
        exit 1
    fi

    # Check if pip3 is installed
    if ! command_exists pip3; then
        print_status "Installing pip3..."
        sudo apt update
        sudo apt install -y python3-pip
    fi

    # Create virtual environment if it doesn't exist
    if [ ! -d ".venv" ]; then
        print_status "Creating virtual environment..."
        python3 -m venv .venv
    fi

    # Install MkDocs and plugins in virtual environment
    print_status "Installing MkDocs and Material theme..."
    source .venv/bin/activate
    pip install --upgrade pip
    pip install mkdocs mkdocs-material
    pip install mkdocs-git-revision-date-localized-plugin
    deactivate

    # Add pip user bin to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        export PATH="$HOME/.local/bin:$PATH"
    fi

    print_success "MkDocs installation completed!"
}

# Function to serve documentation
serve_docs() {
    local host="${1:-127.0.0.1}"
    local port="${2:-8000}"

    print_status "Starting MkDocs development server..."
    print_status "Host: $host"
    print_status "Port: $port"
    print_status "URL: http://$host:$port"
    print_status ""
    print_status "Press Ctrl+C to stop the server"
    print_status ""

    source .venv/bin/activate
    mkdocs serve --dev-addr="$host:$port"
    deactivate
}

# Function to build documentation
build_docs() {
    print_status "Building static documentation..."
    source .venv/bin/activate
    mkdocs build
    deactivate
    print_success "Documentation built successfully!"
    print_status "Static files available in: $SCRIPT_DIR/site/"
}

# Function to show help
show_help() {
    echo "PRS Documentation Server"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  serve     Serve documentation locally (default)"
    echo "  build     Build static documentation"
    echo "  install   Install MkDocs and dependencies"
    echo "  help      Show this help message"
    echo ""
    echo "Serve Options:"
    echo "  --host HOST    Host to bind to (default: 127.0.0.1)"
    echo "  --port PORT    Port to bind to (default: 8000)"
    echo "  --public       Bind to all interfaces (0.0.0.0)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Serve on localhost:8000"
    echo "  $0 serve --port 8080         # Serve on localhost:8080"
    echo "  $0 serve --public            # Serve on all interfaces"
    echo "  $0 build                     # Build static site"
    echo "  $0 install                   # Install MkDocs"
}

# Main script logic
main() {
    local command="${1:-serve}"
    local host="127.0.0.1"
    local port="8000"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            serve)
                command="serve"
                shift
                ;;
            build)
                command="build"
                shift
                ;;
            install)
                command="install"
                shift
                ;;
            help|--help|-h)
                show_help
                exit 0
                ;;
            --host)
                host="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --public)
                host="0.0.0.0"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Check if MkDocs is installed
    if ! command_exists mkdocs && [ "$command" != "install" ]; then
        print_warning "MkDocs is not installed."
        read -p "Would you like to install it now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_mkdocs
        else
            print_error "MkDocs is required to serve documentation."
            print_status "Run '$0 install' to install MkDocs."
            exit 1
        fi
    fi

    # Execute command
    case $command in
        serve)
            serve_docs "$host" "$port"
            ;;
        build)
            build_docs
            ;;
        install)
            install_mkdocs
            ;;
        *)
            print_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
