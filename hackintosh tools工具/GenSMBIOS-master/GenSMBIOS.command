#!/usr/bin/env python
import os, subprocess, shlex, datetime, sys, plistlib, tempfile, shutil, random, uuid, zipfile
from Scripts import *
from collections import OrderedDict
# Python-aware urllib stuff
if sys.version_info >= (3, 0):
    from urllib.request import urlopen
else:
    from urllib2 import urlopen

class Smbios:
    def __init__(self):
        self.u = utils.Utils("GenSMBIOS")
        self.d = downloader.Downloader()
        self.r = run.Run()
        self.url = "https://github.com/acidanthera/MacInfoPkg/releases/latest"
        self.scripts = "Scripts"
        self.plist = None
        self.plist_data = None
        self.plist_type = "Unknown" # Can be "Clover" or "OpenCore" depending
        self.remote = self._get_remote_version()
        self.okay_keys = [
            "SerialNumber",
            "BoardSerialNumber",
            "SmUUID",
            "ProductName",
            "Trust",
            "Memory"
        ]

    def _get_macserial_url(self):
        # Get the latest version of macserial
        try:
            urlsource = self.d.get_string(self.url,False)
            versions = [[y for y in x.split('"') if ".zip" in y and "download" in y] for x in urlsource.lower().split("\n") if any(y in x for y in ("mac.zip","win32.zip","linux.zip")) and "download" in x]
            versions = [x[0] for x in versions]
            mac_version = next(("https://github.com" + x for x in versions if "mac.zip" in x),None)
            win_version = next(("https://github.com" + x for x in versions if "win32.zip" in x),None)
            lin_version = next(("https://github.com" + x for x in versions if "linux.zip" in x),None)
        except:
            # Not valid data
            return None
        return (mac_version,win_version,lin_version)

    def _get_binary(self,binary_name=None):
        if not binary_name:
            binary_name = "macserial32.exe" if os.name == "nt" else "macserial"
        # Check locally
        cwd = os.getcwd()
        os.chdir(os.path.dirname(os.path.realpath(__file__)))
        path = None
        if os.path.exists(binary_name):
            path = os.path.join(os.getcwd(), binary_name)
        elif os.path.exists(os.path.join(os.getcwd(), self.scripts, binary_name)):
            path = os.path.join(os.getcwd(),self.scripts,binary_name)
        os.chdir(cwd)
        return path

    def _get_version(self,macserial):
        # Gets the macserial version
        out, error, code = self.r.run({"args":[macserial]})
        if not len(out):
            return None
        for line in out.split("\n"):
            if not line.lower().startswith("version"):
                continue
            vers = next((x for x in line.lower().strip().split() if len(x) and x[0] in "0123456789"),None)
            if not vers == None and vers[-1] == ".":
                vers = vers[:-1]
            return vers
        return None

    def _download_and_extract(self, temp, url):
        ztemp = tempfile.mkdtemp(dir=temp)
        zfile = os.path.basename(url)
        print("Downloading {}...".format(os.path.basename(url)))
        self.d.stream_to_file(url, os.path.join(ztemp,zfile), False)
        print(" - Extracting...")
        btemp = tempfile.mkdtemp(dir=temp)
        # Extract with built-in tools \o/
        with zipfile.ZipFile(os.path.join(ztemp,zfile)) as z:
            z.extractall(os.path.join(temp,btemp))
        script_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)),self.scripts)
        for x in os.listdir(os.path.join(temp,btemp)):
            if "macserial" in x.lower():
                # Found one
                print(" - Found {}".format(x))
                if os.name != "nt":
                    print("   - Chmod +x...")
                    self.r.run({"args":["chmod","+x",os.path.join(btemp,x)]})
                print("   - Copying to {} directory...".format(self.scripts))
                if not os.path.exists(script_dir):
                    os.mkdir(script_dir)
                shutil.copy(os.path.join(btemp,x), os.path.join(script_dir,x))

    def _get_macserial(self):
        # Download both the windows and mac versions of macserial and expand them to the Scripts dir
        self.u.head("Getting MacSerial")
        print("")
        print("Gathering latest macserial info...")
        urls = self._get_macserial_url()
        if not urls or not len(urls)==3:
            print("Error checking for updates (network issue)\n")
            self.u.grab("Press [enter] to return...")
            return
        systems = {
            "darwin": ["MacURL",urls[0]],
            "win32":  ["WindowsURL",urls[1]],
            "linux":  ["LinuxURL",urls[2]]
        }
        # Download the zips
        temp = tempfile.mkdtemp()
        cwd = os.getcwd()
        try:
            system = "linux" if sys.platform.lower().startswith("linux") else sys.platform
            current = systems[system]
            print(" - {}: {}\n".format(*current))
            self._download_and_extract(temp,current[1])
        except Exception as e:
            print("We ran into some problems :(\n\n{}".format(e))
        print("\nCleaning up...")
        os.chdir(cwd)
        shutil.rmtree(temp)
        self.u.grab("\nDone.",timeout=5)
        return

    def _get_remote_version(self):
        self.u.head("Getting MacSerial Remote Version")
        print("")
        print("Gathering latest macserial info...")
        urls = self._get_macserial_url()
        if not urls:
            print("Error checking for updates (network issue)\n")
            self.u.grab("Press [enter] to return...")
            return None
        try:
            return urls[0].split("/")[7]
        except:
            print("Error parsing update url\n")
            self.u.grab("Press [enter] to return...")
            return None

    def _get_plist(self):
        self.u.head("Select Plist")
        print("")
        print("Current: {}".format(self.plist))
        print("Type:    {}".format(self.plist_type))
        print("")
        print("C. Clear Selection")
        print("M. Main Menu")
        print("Q. Quit")
        print("")
        p = self.u.grab("Please drag and drop the target plist:  ")
        if p.lower() == "q":
            self.u.custom_quit()
        elif p.lower() == "m":
            return
        elif p.lower() == "c":
            self.plist = None
            self.plist_data = None
            return
        
        pc = self.u.check_path(p)
        if not pc:
            self.u.head("File Missing")
            print("")
            print("Plist file not found:\n\n{}".format(p))
            print("")
            self.u.grab("Press [enter] to return...")
            return self._get_plist()
        try:
            with open(pc, "rb") as f:
                self.plist_data = plist.load(f,dict_type=OrderedDict)
        except Exception as e:
            self.u.head("Plist Malformed")
            print("")
            print("Plist file malformed:\n\n{}".format(e))
            print("")
            self.u.grab("Press [enter] to return...")
            return self._get_plist()
        # Got a valid plist - let's try to check for Clover or OC structure
        detected_type = "OpenCore" if "PlatformInfo" in self.plist_data else "Clover" if "SMBIOS" in self.plist_data else "Unknown"
        if detected_type.lower() == "unknown":
            # Have the user decide which to do
            while True:
                self.u.head("Unknown Plist Type")
                print("")
                print("Could not auto-determine plist type!")
                print("")
                print("1. Clover")
                print("2. OpenCore")
                print("")
                print("M. Return to the Menu")
                print("")
                t = self.u.grab("Please select the target type:  ").lower()
                if t == "m": return self._get_plist()
                elif t in ("1","2"):
                    detected_type = "Clover" if t == "1" else "OpenCore"
                    break
        # Got a plist and type - let's save it
        self.plist_type = detected_type
        # Apply any key-stripping or safety checks
        if self.plist_type.lower() == "clover":
            # Got a valid clover plist - let's check keys
            key_check = self.plist_data.get("SMBIOS",{})
            new_smbios = {}
            removed_keys = []
            for key in key_check:
                if key not in self.okay_keys:
                    removed_keys.append(key)
                else:
                    # Build our new SMBIOS
                    new_smbios[key] = key_check[key]
            # We want the SmUUID to be the top-level - remove CustomUUID if exists
            if "CustomUUID" in self.plist_data.get("SystemParameters",{}):
                removed_keys.append("CustomUUID")
            if len(removed_keys):
                while True:
                    self.u.head("")
                    print("")
                    print("The following keys will be removed:\n\n{}\n".format(", ".join(removed_keys)))
                    con = self.u.grab("Continue? (y/n):  ")
                    if con.lower() == "y":
                        # Flush settings
                        self.plist_data["SMBIOS"] = new_smbios
                        # Remove the CustomUUID if present
                        self.plist_data.get("SystemParameters",{}).pop("CustomUUID", None)
                        break
                    elif con.lower() == "n":
                        self.plist_data = None
                        return
        self.plist = pc

    def _get_smbios(self, macserial, smbios_type, times=1):
        # Returns a list of SMBIOS lines that match
        total = []
        while len(total) < times:
            total_len = len(total)
            smbios, err, code = self.r.run({"args":[macserial,"-a"]})
            if code != 0:
                # Issues generating
                return None
            # Got our text, let's see if the SMBIOS exists
            for line in smbios.split("\n"):
                line = line.strip()
                if line.lower().startswith(smbios_type.lower()):
                    total.append(line)
                    if len(total) >= times:
                        break
            if total_len == len(total):
                # Total didn't change - return False
                return False
        # Have a list now - let's format it
        output = []
        for sm in total:
            s_list = [x.strip() for x in sm.split("|")]
            # Add a uuid
            s_list.append(str(uuid.uuid4()).upper())
            # Format the text
            output.append(s_list)
        return output

    def _generate_smbios(self, macserial):
        if not macserial or not os.path.exists(macserial):
            # Attempt to download
            self._get_macserial()
            # Check it again
            macserial = self._get_binary()
            if not macserial or not os.path.exists(macserial):
                # Could not find it, and it failed to download :(
                self.u.head("Missing MacSerial")
                print("")
                print("MacSerial binary was not found and failed to download.")
                print("")
                self.u.grab("Press [enter] to return...")
                return
        self.u.head("Generate SMBIOS")
        print("")
        print("M. Main Menu")
        print("Q. Quit")
        print("")
        print("Please type the SMBIOS to gen and the number")
        menu = self.u.grab("of times to generate [max 20] (i.e. iMac18,3 5):  ")
        if menu.lower() == "q":
            self.u.custom_quit()
        elif menu.lower() == "m":
            return
        menu = menu.split(" ")
        if len(menu) == 1:
            # Default of one time
            smtype = menu[0]
            times  = 1
        else:
            smtype = menu[0]
            try:
                times  = int(menu[1])
            except:
                self.u.head("Incorrect Input")
                print("")
                print("Incorrect format - must be SMBIOS times - i.e. iMac18,3 5")
                print("")
                self.u.grab("Press [enter] to return...")
                self._generate_smbios(macserial)
                return
        # Keep it between 1 and 20
        if times < 1:
            times = 1
        if times > 20:
            times = 20
        smbios = self._get_smbios(macserial,smtype,times)
        if smbios == None:
            # Issues generating
            print("Error - macserial returned an error!")
            self.u.grab("Press [enter] to return...")
            return
        if smbios == False:
            print("\nError - {} not generated by macserial\n".format(smtype))
            self.u.grab("Press [enter] to return...")
            return
        self.u.head("{} SMBIOS Info".format(smbios[0][0]))
        print("")
        print("\n\n".join(["Type:         {}\nSerial:       {}\nBoard Serial: {}\nSmUUID:       {}".format(x[0], x[1], x[2], x[3]) for x in smbios]))
        if self.plist_data and self.plist and os.path.exists(self.plist):
            # Let's apply - got a valid file, and plist data
            if len(smbios) > 1:
                print("\nFlushing first SMBIOS entry to {}".format(self.plist))
            else:
                print("\nFlushing SMBIOS entry to {}".format(self.plist))
            if self.plist_type.lower() == "clover":
                # Ensure plist data exists
                for x in ["SMBIOS","RtVariables","SystemParameters"]:
                    if not x in self.plist_data:
                        self.plist_data[x] = {}
                self.plist_data["SMBIOS"]["ProductName"] = smbios[0][0]
                self.plist_data["SMBIOS"]["SerialNumber"] = smbios[0][1]
                self.plist_data["SMBIOS"]["BoardSerialNumber"] = smbios[0][2]
                self.plist_data["RtVariables"]["MLB"] = smbios[0][2]
                self.plist_data["SMBIOS"]["SmUUID"] = smbios[0][3]
                self.plist_data["SystemParameters"]["InjectSystemID"] = True
            elif self.plist_type.lower() == "opencore":
                # Ensure data exists
                if not "PlatformInfo" in self.plist_data: self.plist_data["PlatformInfo"] = {}
                if not "Generic" in self.plist_data["PlatformInfo"]: self.plist_data["PlatformInfo"]["Generic"] = {}
                # Set the values
                self.plist_data["PlatformInfo"]["Generic"]["SystemProductName"] = smbios[0][0]
                self.plist_data["PlatformInfo"]["Generic"]["SystemSerialNumber"] = smbios[0][1]
                self.plist_data["PlatformInfo"]["Generic"]["MLB"] = smbios[0][2]
                self.plist_data["PlatformInfo"]["Generic"]["SystemUUID"] = smbios[0][3]
            with open(self.plist, "wb") as f:
                plist.dump(self.plist_data, f, sort_keys=False)
            # Got only valid keys now
        print("")
        self.u.grab("Press [enter] to return...")

    def _list_current(self, macserial):
        if not macserial or not os.path.exists(macserial):
            self.u.head("Missing MacSerial")
            print("")
            print("MacSerial binary not found.")
            print("")
            self.u.grab("Press [enter] to return...")
            return
        out, err, code = self.r.run({"args":[macserial]})
        out = "\n".join([x for x in out.split("\n") if not x.lower().startswith("version") and len(x)])
        self.u.head("Current SMBIOS Info")
        print("")
        print(out)
        print("")
        self.u.grab("Press [enter] to return...")

    def main(self):
        self.u.head()
        print("")
        macserial = self._get_binary()
        if macserial:
            macserial_v = self._get_version(macserial)
            print("MacSerial v{}".format(macserial_v))
        else:
            macserial_v = "0.0.0"
            print("MacSerial not found!")
        # Print remote version if possible
        if self.remote and self.u.compare_versions(macserial_v, self.remote):
            print("Remote Version v{}".format(self.remote))
        print("Current plist: {}".format(self.plist))
        print("Plist type:    {}".format(self.plist_type))
        print("")
        print("1. Install/Update MacSerial")
        print("2. Select config.plist")
        print("3. Generate SMBIOS")
        print("4. Generate UUID")
        print("5. List Current SMBIOS")
        print("")
        print("Q. Quit")
        print("")
        menu = self.u.grab("Please select an option:  ").lower()
        if not len(menu):
            return
        if menu == "q":
            self.u.custom_quit()
        elif menu == "1":
            self._get_macserial()
        elif menu == "2":
            self._get_plist()
        elif menu == "3":
            self._generate_smbios(macserial)
        elif menu == "4":
            self.u.head("Generated UUID")
            print("")
            print(str(uuid.uuid4()).upper())
            print("")
            self.u.grab("Press [enter] to return...")
        elif menu == "5":
            self._list_current(macserial)

s = Smbios()
while True:
    try:
        s.main()
    except Exception as e:
        print(e)
        if sys.version_info >= (3, 0):
            input("Press [enter] to return...")
        else:
            raw_input("Press [enter] to return...")
