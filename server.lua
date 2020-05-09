package.loaded.socket = nil
package.loaded.FTPCC = nil
require("FTPCC").server(peripheral.find("modem")):listen()
