FROM mcr.microsoft.com/azure-cli:latest

# Install kubectl using Azure CLI
RUN az aks install-cli

# Verify kubectl installation
RUN kubectl version --client

# Set working directory
WORKDIR /

# Copy the script into the image
COPY namespace-cleaner.sh /namespace-cleaner.sh
RUN chmod +x /namespace-cleaner.sh

# Entry point to run the script
ENTRYPOINT ["/bin/sh", "-c", "/namespace-cleaner.sh"]
