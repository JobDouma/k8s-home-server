terraform {
  required_version = ">= 1.5.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    # The brennoo/hrui provider is intentionally disabled: nothing in this
    # repo uses it. Re-enable it (and add a matching `provider "hrui"` block
    # in a new providers.tf) if you later migrate to it.
    #
    # hrui = {
    #   source  = "brennoo/hrui"
    #   version = "= 0.1.4"
    # }
  }
}