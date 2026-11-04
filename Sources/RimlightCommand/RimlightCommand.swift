/// The `rimlight` command, for the package's executable and the app's embedded copy.
public enum RimlightCommand {
    /// Runs one command line, without the program name. Returns the exit status: 0 on
    /// success, 1 on a failure, 2 on a usage error.
    public static func main(_ arguments: [String]) -> Int32 {
        CLI.main(arguments)
    }
}
