# Same Free Edition workspace as healthkit-medallion-pipeline -- Free
# Edition allows exactly one workspace per account, so this can't be a
# different workspace even if it wanted to be. With a new datajobs profile rather than creating a new one, since
# it already points at the right host with working auth.
provider "databricks" {
  profile = "datajobs"
}
