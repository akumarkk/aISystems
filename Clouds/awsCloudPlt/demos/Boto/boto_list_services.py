import boto3

session = boto3.Session()
# Gets a list of all service names supported by your installed version of boto3
available_services = session.get_available_services()
print(available_services)